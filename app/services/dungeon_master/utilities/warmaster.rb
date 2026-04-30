# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Warmaster — combat initialization utility.
    #
    # Creates creature sheets, rolls creature initiative, and prepares
    # combat_context for the adventure. Supports two entry paths:
    #
    #   Path A (Encounter table): receives an EncounterTableEntry with a
    #           creature_manifest for deterministic spawning.
    #   Path B (Narrative-originated): receives a list of combatant names
    #           from the combat beacon for fuzzy bestiary + dynamic creation.
    #
    # Returns { status: :awaiting_initiative, ... } so the pipeline can
    # pause and ask the player to roll initiative. If the player ignores
    # the prompt, the pipeline auto-rolls using their DEX modifier.
    module Warmaster
      include Mutations

      module_function

      # Path A: from Harbinger encounter table roll
      # creatures_data:    optional structured array from encounter_expand AI (via AdventureLoop)
      #                    e.g. [{ "name" => "goblin", "count" => 4 }]
      # scene_enemy_names: optional array of creature-type strings extracted from
      #                    traversal_context["nearby_npcs"] by EncounterWarmasterBridge.
      #                    These are merged in after the encounter-table creatures so that
      #                    pre-established scene enemies join the combat.
      def initialize_from_encounter!(encounter_initialization_request: nil, **kwargs)
        encounter_initialization_request ||= EncounterInitializationRequest.new(**kwargs)
        warmaster_context = Context.new(
          adventure: encounter_initialization_request.adventure,
          sheet: encounter_initialization_request.sheet,
          log: encounter_initialization_request.log,
          config: encounter_initialization_request.config,
          ai: encounter_initialization_request.ai
        )

        creatures = if encounter_initialization_request.encounter_entry.has_manifest?
                      spawn_from_manifest(warmaster_context, encounter_initialization_request.encounter_entry.creature_manifest)
                    elsif encounter_initialization_request.creatures_data.is_a?(Array) && encounter_initialization_request.creatures_data.any?
                      names = encounter_initialization_request.creatures_data.flat_map do |c|
                        name = (c["name"] || c[:name] || "creature").to_s.singularize
                        count = (c["count"] || c[:count] || 1).to_i.clamp(1, 20)
                        Array.new(count, name)
                      end
                      spawn_from_names(warmaster_context, names)
                    else
                      encounter_initialization_request.log.log!(
                        :warn,
                        "Warmaster: no manifest or creatures_data for entry '#{encounter_initialization_request.encounter_entry.title}' — cannot spawn creatures"
                      )
                      []
                    end

        creatures = merge_scene_enemy_names(warmaster_context, creatures, encounter_initialization_request.scene_enemy_names)

        build_initiative_result(warmaster_context, creatures)
      end

      # Path B: from combat beacon combatant names
      def initialize_from_names!(names_preparation_request: nil, **kwargs)
        names_preparation_request ||= NamesPreparationRequest.new(**kwargs)
        warmaster_context = Context.new(
          adventure: names_preparation_request.adventure,
          sheet: names_preparation_request.sheet,
          log: names_preparation_request.log,
          config: names_preparation_request.config,
          ai: names_preparation_request.ai
        )
        creatures = prepare_from_names!(names_preparation_request: names_preparation_request)[:creatures]
        build_initiative_result(warmaster_context, creatures)
      end

      # Path C: eager canonical creature prep for combat-starting actions before mech-eval.
      # Creates / reuses creature sheets and rolls NPC initiative before combat activation.
      def prepare_from_names!(names_preparation_request: nil, **kwargs)
        names_preparation_request ||= NamesPreparationRequest.new(**kwargs)
        warmaster_context = Context.new(
          adventure: names_preparation_request.adventure,
          sheet: names_preparation_request.sheet,
          log: names_preparation_request.log,
          config: names_preparation_request.config,
          ai: names_preparation_request.ai
        )
        names = expand_combatant_names(names_preparation_request.combatant_names, names_preparation_request.count)
        creatures = spawn_from_names(warmaster_context, names)
        creature_data = prepare_creature_data(warmaster_context, creatures)

        {
          status: creature_data.any? ? :prepared : :no_creatures,
          creature_data: creature_data,
          creatures: creatures
        }
      end

      # Compute the finalized combat state from creature data and player initiative.
      # Pure computation — does NOT write to the adventure record.
      # Returns a hash suitable for passing as combat_initialization in mutations,
      # which ContextUpdate will write verbatim to adventure.combat_context.
      #
      # +adventure+ and +player_sheet+ are required to load canonical HP/conditions from sheets.
      def compute_combat_initialization(combat_initialization_request: nil, **kwargs)
        combat_initialization_request ||= CombatInitializationRequest.new(**kwargs)
        raise ArgumentError, "player_sheet required for combat initialization" unless combat_initialization_request.player_sheet

        npc_combatants = pending_npc_combatants(combat_initialization_request.adventure, combat_initialization_request.player_sheet).presence ||
                         combat_initialization_request.creature_data.filter_map do |c|
                           next unless c.is_a?(Hash)

                           c = c.deep_symbolize_keys
                           sheet = combat_initialization_request.adventure.creature_sheets.find_by(id: c[:creature_sheet_id])
                           unless sheet
                             Rails.logger.warn("[Warmaster] creature_sheet id=#{c[:creature_sheet_id]} not found — omitted from combat")
                             next
                           end

                           Combatant.from_creature_sheet(sheet, initiative: c[:initiative].to_i)
                         end

        player_combatant = Combatant.from_player_sheet(
          combat_initialization_request.player_sheet,
          initiative: combat_initialization_request.player_initiative.to_i
        )
        all_ordered = (npc_combatants + [player_combatant]).sort_by { |p| -p.initiative }
        turn_order = all_ordered.map(&:name)
        current_turn = turn_order.first

        participants = all_ordered.map(&:to_context_hash)

        {
          "active" => true,
          "round" => 1,
          "current_turn" => current_turn,
          "turn_order" => turn_order,
          "participants" => participants,
          "terrain_notes" => nil
        }
      end

      def persist_pending_combat!(adventure:, creature_data:)
        pending = compute_pending_combat_context(adventure: adventure, creature_data: creature_data)
        adventure.update!(combat_context: pending)
        pending
      end

      def compute_pending_combat_context(adventure:, creature_data:)
        npc_combatants = creature_data.filter_map do |c|
          next unless c.is_a?(Hash)

          row = c.deep_symbolize_keys
          sheet = adventure.creature_sheets.find_by(id: row[:creature_sheet_id])
          unless sheet
            Rails.logger.warn("[Warmaster] creature_sheet id=#{row[:creature_sheet_id]} not found — omitted from pending combat")
            next
          end

          Combatant.from_creature_sheet(sheet, initiative: row[:initiative].to_i)
        end.sort_by { |combatant| -combatant.initiative }

        CombatContext.pending(
          participants: npc_combatants.map(&:to_context_hash),
          current_turn: npc_combatants.first&.name,
          turn_order: npc_combatants.map(&:name),
          terrain_notes: nil
        )
      end

      # Auto-roll player initiative from their character sheet
      def auto_roll_player_initiative(sheet)
        dex_mod = sheet ? ((sheet.dexterity - 10).to_f / 2).floor : 0
        roll = rand(1..20)
        roll + dex_mod
      end

      # ---- Internal context carrier ----

      class Context
        attr_reader :adventure, :sheet, :log, :config, :ai

        def initialize(adventure:, sheet:, log:, config:, ai:)
          @adventure = adventure
          @sheet = sheet
          @log = log
          @config = config
          @ai = ai
        end
      end

      # ---- Spawning ----

      def spawn_from_manifest(ctx, manifest)
        creatures = []
        Array(manifest).each do |entry|
          bestiary_id = entry["bestiary_entry_id"]
          count = (entry["count"] || 1).to_i
          display_base = entry["display_name"] || bestiary_id || "Creature"

          count.times.each_with_index do |_, i|
            display_name = count > 1 ? "#{display_base} #{i + 1}" : display_base
            sheet = resolve_creature(ctx, bestiary_id || display_base, display_name)
            creatures << creature_record(sheet, display_name) if sheet
          end
        end
        creatures
      end

      def spawn_from_names(ctx, names)
        name_counts = Hash.new(0)
        creatures = []

        Array(names).each do |raw_name|
          name = TextNormalizer.strip(raw_name)
          next if name.blank?

          name_counts[name] += 1
          display_name = name_counts[name] > 1 ? "#{name.titleize} #{name_counts[name]}" : name.titleize

          existing = ctx.adventure.creature_sheets.find_by(name: display_name)
          if existing
            creatures << creature_record(existing, display_name)
            next
          end

          sheet = resolve_creature(ctx, name, display_name)
          creatures << creature_record(sheet, display_name) if sheet
        end

        creatures
      end

      def resolve_creature(ctx, lookup_name, display_name)
        existing = ctx.adventure.creature_sheets.find_by(name: display_name)
        return existing if existing

        bestiary = fuzzy_bestiary_match_static(lookup_name)
        if bestiary
          create_creature_from_bestiary_static(ctx, bestiary, display_name)
        else
          dynamic_creature_sheet_static(ctx, display_name, party_level: ctx.sheet&.level || 1)
        end
      end

      def merge_scene_enemy_names(ctx, creatures, scene_enemy_names)
        # Merge scene enemies (hostile NPCs already established in traversal_context).
        # Skip any whose creature-type name overlaps with an encounter creature already spawned
        # to avoid doubling up (e.g. encounter already has orcs, nearby_npcs also says "orc patrol").
        novel_scene_names = Array(scene_enemy_names).reject do |scene_name|
          normalized_scene_name = TextNormalizer.normalized_key(scene_name)
          creatures.any? do |creature|
            normalized_creature_name = TextNormalizer.normalized_key(creature[:name])
            creature_first_token = normalized_creature_name.split.first.to_s

            normalized_creature_name.include?(normalized_scene_name) ||
              normalized_scene_name.include?(creature_first_token)
          end
        end

        if novel_scene_names.any?
          ctx.log.log!(:info, "Warmaster: merging #{novel_scene_names.size} scene enemy type(s) from traversal context: #{novel_scene_names.inspect}")
          creatures + spawn_from_names(ctx, novel_scene_names)
        else
          creatures
        end
      end

      def expand_combatant_names(combatant_names, count)
        names = Array(combatant_names).map { |name| TextNormalizer.strip(name) }.reject(&:blank?)
        qty = count.to_i
        return names unless names.one? && qty > 1

        Array.new(qty, names.first)
      end

      def pending_npc_combatants(adventure, player_sheet)
        combat_context = adventure.combat_context
        return [] unless combat_context.is_a?(Hash) && combat_context["active"] != true

        participants = Array(combat_context["participants"])
        return [] if participants.empty?

        return [] if participants.any? { |participant| participant["type"].to_s == "player" }

        participants.filter_map do |participant|
          next if participant["type"].to_s == "player"

          refreshed = Combatant.refresh_from_live_sources(participant, adventure: adventure, sheet: player_sheet)
          Combatant.from_context_hash(refreshed)
        end
      end

      # ---- Initiative ----

      def build_initiative_result(ctx, creatures)
        if creatures.empty?
          ctx.log.play_log!("warmaster", "Combat aborted: no creatures created")
          return { status: :no_creatures }
        end

        creature_data = prepare_creature_data(ctx, creatures)

        creature_names = creature_data.map { |c| "#{c[:name]} (init #{c[:initiative]})" }
        ctx.log.play_log!("warmaster", "Combat: #{creature_data.size} creature(s) ready",
                          parsed_response: { creature_count: creature_data.size, creatures: creature_names })

        { status: :awaiting_initiative, creature_data: creature_data }
      end

      def prepare_creature_data(ctx, creatures)
        creatures.map do |c|
          initiative = roll_creature_initiative(ctx, c[:creature_sheet_id])
          c.merge(initiative: initiative)
        end
      end

      def roll_creature_initiative(ctx, creature_sheet_id)
        creature = ctx.adventure.creature_sheets.find_by(id: creature_sheet_id)
        return rand(1..20) unless creature

        dex_mod = ((creature.dexterity - 10).to_f / 2).floor
        feat_bonus = creature.feat_definitions.exists?(name: "Improved Initiative") ? 4 : 0
        rand(1..20) + dex_mod + feat_bonus
      end

      # ---- Static wrappers for Mutations methods ----

      def fuzzy_bestiary_match_static(name)
        return nil unless defined?(BestiaryEntry)

        normalized = TextNormalizer.normalized_key(name).singularize
        BestiaryEntry.find_by("LOWER(name) = ?", normalized) ||
          BestiaryEntry.where("LOWER(name) LIKE ?", "%#{normalized}%").first ||
          BestiaryEntry.find_by(id: TextNormalizer.singular_identifier(normalized)) ||
          first_token_bestiary_match(normalized)
      end

      # "Goblin Scout" / "Orc Warboss Vanguard" → fall back to the first token
      # ("goblin" / "orc"). Without this every multi-word variant misses the
      # canonical SRD entry and falls through to the AI fallback, which has
      # historically been free to invent CR-18, 90-HP minions for a level-1
      # party. Cheap dictionary lookup before the AI is the right backstop.
      def first_token_bestiary_match(normalized)
        head = normalized.split(/[_\s]+/).first.to_s.singularize
        return nil if head.blank? || head == normalized

        BestiaryEntry.find_by("LOWER(name) = ?", head) ||
          BestiaryEntry.find_by(id: head)
      end

      def create_creature_from_bestiary_static(ctx, entry, display_name)
        hp = roll_hp_static(entry.hp_formula)
        attrs = entry.to_creature_sheet_attrs(display_name: display_name)
        sheet = ctx.adventure.creature_sheets.create!(attrs.merge(hp: hp, max_hp: hp, origin: "bestiary"))
        sheet.recompute_derived_stats!
        sheet
      end

      def dynamic_creature_sheet_static(ctx, name, party_level:)
        mode = ctx.config.get("creature_creation_fallback") || "ai"
        case mode
        when "ai"       then create_from_ai_static(ctx, name, party_level)
        when "template" then create_from_template_static(ctx, name, party_level)
        else nil
        end
      rescue => e
        ctx.log.log!(:error, "[warmaster_creature] #{e.class}: #{e.message}")
        raise
      end

      CREATURE_TEMPLATE = {
        1 => { str: 13, dex: 13, con: 12, int: 6, wis: 10, cha: 8, ac: 13, bab: 1, hp: "1d10+2", speed: 30 },
        2 => { str: 14, dex: 13, con: 13, int: 6, wis: 10, cha: 8, ac: 14, bab: 2, hp: "2d10+4", speed: 30 },
        3 => { str: 15, dex: 14, con: 13, int: 7, wis: 11, cha: 8, ac: 15, bab: 3, hp: "3d10+6", speed: 30 },
        5 => { str: 17, dex: 14, con: 14, int: 8, wis: 11, cha: 9, ac: 17, bab: 5, hp: "5d10+10", speed: 30 },
        8 => { str: 19, dex: 15, con: 16, int: 8, wis: 12, cha: 10, ac: 20, bab: 8, hp: "8d10+24", speed: 30 },
        10 => { str: 21, dex: 16, con: 17, int: 9, wis: 12, cha: 10, ac: 22, bab: 10, hp: "10d10+30", speed: 30 },
      }.freeze

      def create_from_template_static(ctx, name, party_level)
        tier = CREATURE_TEMPLATE.keys.select { |k| k <= party_level }.max || 1
        stats = CREATURE_TEMPLATE[tier]
        hp = roll_hp_static(stats[:hp])

        sheet = ctx.adventure.creature_sheets.create!(
          name: name, creature_type: "monster", origin: "template",
          strength: stats[:str], dexterity: stats[:dex], constitution: stats[:con],
          intelligence: stats[:int], wisdom: stats[:wis], charisma: stats[:cha],
          level: [party_level, 1].max, hp: hp, max_hp: hp,
          derived_stats: { "ac" => stats[:ac], "bab" => stats[:bab], "speed" => stats[:speed] }
        )
        sheet.recompute_derived_stats!
        sheet
      end

      def create_from_ai_static(ctx, name, party_level)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw_response = nil
        prompt_summary = "Warmaster/CreatureGeneration: #{name} (party level #{party_level})"

        system_prompt, user_msg = PromptRenderer.render_with_user_message("creature_generation",
          creature_name: name, party_level: party_level)

        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw_response = ctx.ai.chat(
          system_prompt: system_prompt,
          user_message: user_msg,
          max_tokens: ctx.config.token_budget_for("creature_generation"),
          step_name: "creature_generation",
          model: ctx.config.model_for("creature_generation"))

        parsed = ctx.ai.parse_json(raw_response)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        ctx.log.ai_log!("creature_generation", prompt_summary, raw_response, parsed,
                        parse_status: ctx.ai.last_parse_status, request_body: request_body,
                        model_used: ctx.ai.last_model_used, duration_ms: duration_ms,
                        usage: ctx.ai.last_usage)

        # The prompt advises CR ≈ party_level ±2 but the AI ignores it freely
        # (observed: "Goblin Scout" returned at CR 18 / 85 HP for a level-1
        # party). Hard-clamp on the receiving side: CR upper bound is
        # party_level + 2, HP rolled from formula then capped against a
        # CR-derived ceiling so a wild hp_formula can't smuggle in a tank.
        cr = parsed["cr"].to_i.clamp(1, [party_level + 2, 1].max)
        hp_rolled = roll_hp_static(parsed["hp_formula"])
        hp = [hp_rolled, hp_ceiling_for_cr(cr)].min
        raw_type = TextNormalizer.normalized_key(parsed["creature_type"])
        normalized_type = BestiaryEntry::CREATURE_TYPE_MAP[raw_type] ||
                          (CreatureSheet::CREATURE_TYPES.include?(raw_type) ? raw_type : "monster")
        sheet = ctx.adventure.creature_sheets.create!(
          name: name, creature_type: normalized_type, origin: "ai",
          strength: parsed["strength"].to_i.clamp(1, 40),
          dexterity: parsed["dexterity"].to_i.clamp(1, 40),
          constitution: parsed["constitution"].to_i.clamp(1, 40),
          intelligence: parsed["intelligence"].to_i.clamp(1, 40),
          wisdom: parsed["wisdom"].to_i.clamp(1, 40),
          charisma: parsed["charisma"].to_i.clamp(1, 40),
          level: cr, hp: hp, max_hp: hp,
          derived_stats: {
            "ac" => parsed["ac"].to_i,
            "bab" => parsed["base_attack"].to_i,
            "speed" => parsed["speed"].to_i
          }
        )
        sheet.recompute_derived_stats!
        sheet
      end

      # Rough HP ceiling per CR — covers the upper end of the SRD HP range
      # for that CR (e.g. CR 1 ≈ 12-15 HP, CR 5 ≈ 50-60 HP). 12×CR + 5 keeps
      # CR 1 around 17 HP and CR 10 around 125 HP, which leaves the low CR
      # space tight (where AI hallucinations actually hurt) without over-
      # constraining mid-tier templates.
      def hp_ceiling_for_cr(cr)
        12 * cr + 5
      end

      def roll_hp_static(formula)
        return 10 unless formula.present?

        if formula.to_s =~ /(\d+)d(\d+)([+-]\d+)?/
          count, die, mod = $1.to_i, $2.to_i, ($3 || 0).to_i
          count.times.sum { rand(1..die) } + mod
        else
          formula.to_i.nonzero? || 10
        end
      end

      def creature_record(sheet, display_name)
        { name: display_name, creature_sheet_id: sheet.id }
      end

      private_class_method :spawn_from_manifest, :spawn_from_names, :resolve_creature,
                           :build_initiative_result, :roll_creature_initiative,
                           :fuzzy_bestiary_match_static, :first_token_bestiary_match,
                           :create_creature_from_bestiary_static,
                           :dynamic_creature_sheet_static, :create_from_template_static,
                           :create_from_ai_static, :hp_ceiling_for_cr,
                           :roll_hp_static, :creature_record
    end
  end
end
