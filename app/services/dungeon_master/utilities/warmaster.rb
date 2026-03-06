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
      def initialize_from_encounter!(adventure:, encounter_entry:, sheet:, log:, config:, ai:)
        ctx = Context.new(adventure: adventure, sheet: sheet, log: log, config: config, ai: ai)

        creatures = if encounter_entry.has_manifest?
                      spawn_from_manifest(ctx, encounter_entry.creature_manifest)
                    else
                      spawn_from_names(ctx, extract_names_from_description(encounter_entry.description))
                    end

        build_initiative_result(ctx, creatures)
      end

      # Path B: from combat beacon combatant names
      def initialize_from_names!(adventure:, combatant_names:, sheet:, log:, config:, ai:)
        ctx = Context.new(adventure: adventure, sheet: sheet, log: log, config: config, ai: ai)
        creatures = spawn_from_names(ctx, combatant_names)
        build_initiative_result(ctx, creatures)
      end

      # Final step: complete combat_context with player initiative (called on resume)
      def finalize_combat!(adventure:, creature_data:, player_initiative:)
        participants = creature_data.map do |c|
          { "name" => c[:name], "creature_sheet_id" => c[:creature_sheet_id],
            "initiative" => c[:initiative], "type" => "npc" }
        end
        participants << { "name" => "Player", "initiative" => player_initiative.to_i, "type" => "player" }

        turn_order = participants.sort_by { |p| -p["initiative"] }.map { |p| p["name"] }

        adventure.update!(combat_context: {
          "active" => true, "round" => 1,
          "participants" => participants,
          "turn_order" => turn_order,
          "active_effects" => []
        })
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
          name = raw_name.to_s.strip
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

      # ---- Initiative ----

      def build_initiative_result(ctx, creatures)
        if creatures.empty?
          ctx.log.dm_log!("Warmaster: no creatures could be created — combat initialization aborted")
          return { status: :no_creatures }
        end

        creature_data = creatures.map do |c|
          initiative = roll_creature_initiative(ctx, c[:creature_sheet_id])
          c.merge(initiative: initiative)
        end

        ctx.log.dm_log!("Warmaster: #{creature_data.size} creature(s) ready, awaiting player initiative")

        { status: :awaiting_initiative, creature_data: creature_data }
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

        normalized = name.downcase.strip.singularize
        BestiaryEntry.find_by("LOWER(name) = ?", normalized) ||
          BestiaryEntry.where("LOWER(name) LIKE ?", "%#{normalized}%").first ||
          BestiaryEntry.find_by(id: normalized.gsub(/\s+/, "_"))
      end

      def create_creature_from_bestiary_static(ctx, entry, display_name)
        hp = roll_hp_static(entry.hp_formula)
        attrs = entry.to_creature_sheet_attrs(display_name: display_name)
        ctx.adventure.creature_sheets.create!(attrs.merge(hp: hp, max_hp: hp))
      end

      def dynamic_creature_sheet_static(ctx, name, party_level:)
        mode = ctx.config.get("creature_creation_fallback") || "ai"
        case mode
        when "ai"       then create_from_ai_static(ctx, name, party_level)
        when "template" then create_from_template_static(ctx, name, party_level)
        else nil
        end
      rescue => e
        ctx.log.dm_log!("Warmaster dynamic creature creation failed for '#{name}': #{e.message}")
        nil
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

        ctx.adventure.creature_sheets.create!(
          name: name, creature_type: "monster",
          strength: stats[:str], dexterity: stats[:dex], constitution: stats[:con],
          intelligence: stats[:int], wisdom: stats[:wis], charisma: stats[:cha],
          level: [party_level, 1].max, hp: hp, max_hp: hp,
          derived_stats: { "ac" => stats[:ac], "bab" => stats[:bab], "speed" => stats[:speed] }
        )
      end

      def create_from_ai_static(ctx, name, party_level)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Warmaster/CreatureGeneration: #{name} (party level #{party_level})"

        system_prompt = PromptRenderer.render("creature_generation",
          creature_name: name, party_level: party_level)

        request_body = { system_prompt: system_prompt, user_message: "Generate this creature." }
        raw = ctx.ai.chat(
          system_prompt: system_prompt,
          user_message: "Generate this creature.",
          max_tokens: ctx.config.token_budget_for("creature_generation"),
          step_name: "creature_generation",
          model: ctx.config.model_for("creature_generation"))

        parsed = ctx.ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        ctx.log.ai_log!("creature_generation", prompt_summary, raw, parsed,
                        parse_status: ctx.ai.last_parse_status, request_body: request_body,
                        model_used: ctx.ai.last_model_used, duration_ms: duration_ms,
                        usage: ctx.ai.last_usage)

        hp = roll_hp_static(parsed["hp_formula"])
        ctx.adventure.creature_sheets.create!(
          name: name, creature_type: parsed["creature_type"] || "monster",
          strength: parsed["strength"].to_i.clamp(1, 40),
          dexterity: parsed["dexterity"].to_i.clamp(1, 40),
          constitution: parsed["constitution"].to_i.clamp(1, 40),
          intelligence: parsed["intelligence"].to_i.clamp(1, 40),
          wisdom: parsed["wisdom"].to_i.clamp(1, 40),
          charisma: parsed["charisma"].to_i.clamp(1, 40),
          level: [parsed["cr"].to_i, 1].max, hp: hp, max_hp: hp,
          derived_stats: {
            "ac" => parsed["ac"].to_i,
            "bab" => parsed["base_attack"].to_i,
            "speed" => parsed["speed"].to_i
          }
        )
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

      def extract_names_from_description(description)
        words = description.to_s.downcase
        return [words.scan(/\d+\s+(\w+)/).flatten.first || "creature"] if words.present?
        ["creature"]
      end

      private_class_method :spawn_from_manifest, :spawn_from_names, :resolve_creature,
                           :build_initiative_result, :roll_creature_initiative,
                           :fuzzy_bestiary_match_static, :create_creature_from_bestiary_static,
                           :dynamic_creature_sheet_static, :create_from_template_static,
                           :create_from_ai_static, :roll_hp_static, :creature_record,
                           :extract_names_from_description
    end
  end
end
