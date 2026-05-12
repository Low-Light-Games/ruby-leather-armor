# frozen_string_literal: true

module Encounters
  # Combat persistence + initiative wiring. Identity is owned upstream by
  # `Encounters::CastResolver` (free-text path) or `WarmasterBridge`'s
  # manifest (table-driven encounters), so every NPC arriving here
  # already has a real `actor_sheet_id` to point at.
  module Warmaster
    include Mutations

    module_function

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
                  else
                    encounter_initialization_request.log.log!(
                      :warn,
                      "Warmaster: encounter entry '#{encounter_initialization_request.encounter_entry.title}' has no manifest — cannot spawn creatures (free-text encounters are no longer supported)"
                    )
                    []
                  end

      build_initiative_result(warmaster_context, creatures)
    end

    def compute_combat_initialization(combat_initialization_request: nil, **kwargs)
      combat_initialization_request ||= CombatInitializationRequest.new(**kwargs)
      raise ArgumentError, "player_sheet required for combat initialization" unless combat_initialization_request.player_sheet

      npc_combatants = pending_npc_combatants(combat_initialization_request.adventure, combat_initialization_request.player_sheet).presence ||
                       combat_initialization_request.creature_data.filter_map do |c|
                         next unless c.is_a?(Hash)

                         c = c.deep_symbolize_keys
                         sheet = combat_initialization_request.adventure.adventure_actor_sheets.find_by(id: c[:actor_sheet_id])
                         unless sheet
                           Rails.logger.warn("[Warmaster] adventure_actor_sheet id=#{c[:actor_sheet_id]} not found — omitted from combat")
                           next
                         end

                         Combat::Combatant.from_adventure_actor_sheet(sheet, initiative: c[:initiative].to_i)
                       end

      player_combatant = Combat::Combatant.from_player_sheet(
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
        sheet = adventure.adventure_actor_sheets.find_by(id: row[:actor_sheet_id])
        unless sheet
          Rails.logger.warn("[Warmaster] adventure_actor_sheet id=#{row[:actor_sheet_id]} not found — omitted from pending combat")
          next
        end

        Combat::Combatant.from_adventure_actor_sheet(sheet, initiative: row[:initiative].to_i)
      end.sort_by { |combatant| -combatant.initiative }

      Combat::Context.pending(
        participants: npc_combatants.map(&:to_context_hash),
        current_turn: npc_combatants.first&.name,
        turn_order: npc_combatants.map(&:name),
        terrain_notes: nil
      )
    end

    # @param adventure [Adventure]
    # @param cast_roster [PlayerTurn::CastRoster]
    # @param target_actor_sheet_id [Integer, nil]
    # @return [Hash{Symbol => Object}] :status, plus :creature_data when :awaiting_initiative
    def persist_combat_from_cast_roster!(adventure:, cast_roster:, target_actor_sheet_id: nil)
      combatants = pick_initial_combatants(cast_roster, target_actor_sheet_id)
      return { status: :no_creatures } if combatants.empty?

      creature_data = combatants.map do |member|
        {
          name:              member.name,
          actor_sheet_id:    member.actor_sheet_id,
          initiative:        roll_initiative_for_sheet_id(adventure, member.actor_sheet_id),
        }
      end

      persist_pending_combat!(adventure: adventure, creature_data: creature_data)
      { status: :awaiting_initiative, creature_data: creature_data }
    end

    def pick_initial_combatants(cast_roster, target_actor_sheet_id)
      with_sheets    = cast_roster.members.select(&:actor_sheet_id)
      pre_hostile    = with_sheets.select(&:hostile?)
      target_id      = target_actor_sheet_id.to_i
      target         = (with_sheets.find { |m| m.actor_sheet_id.to_i == target_id } if target_id.positive?)

      ([target].compact + pre_hostile).uniq { |m| m.actor_sheet_id }
    end

    def auto_roll_player_initiative(sheet)
      dex_mod = sheet ? ((sheet.dexterity - 10).to_f / 2).floor : 0
      roll = rand(1..20)
      roll + dex_mod
    end

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

    def spawn_from_manifest(ctx, manifest)
      creatures = []
      Array(manifest).each do |entry|
        bestiary_id  = entry["bestiary_entry_id"]
        count        = (entry["count"] || 1).to_i
        display_base = entry["display_name"] || bestiary_id || "Creature"
        bestiary     = bestiary_id ? BestiaryEntry.find_by(id: bestiary_id) : nil

        unless bestiary
          ctx.log.log!(:warn, "[Warmaster] creature_manifest entry references unknown bestiary_entry_id=#{bestiary_id.inspect}; skipping")
          next
        end

        sheets = Encounters::ActorSheetCreation.from_bestiary(
          adventure:      ctx.adventure,
          bestiary_entry: bestiary,
          display_name:   display_base,
          count:          count,
        )
        sheets.each { |sheet| creatures << creature_record(sheet, sheet.name) }
      end
      creatures
    end

    def pending_npc_combatants(adventure, player_sheet)
      combat_context = adventure.combat_context
      return [] unless combat_context.is_a?(Hash) && combat_context["active"] != true

      participants = Array(combat_context["participants"])
      return [] if participants.empty?

      return [] if participants.any? { |participant| participant["type"].to_s == "player" }

      participants.filter_map do |participant|
        next if participant["type"].to_s == "player"

        refreshed = Combat::Combatant.refresh_from_live_sources(participant, adventure: adventure, sheet: player_sheet)
        Combat::Combatant.from_context_hash(refreshed)
      end
    end

    def build_initiative_result(ctx, creatures)
      if creatures.empty?
        ctx.log.play_log!("warmaster", "Combat aborted: no creatures created")
        return { status: :no_creatures }
      end

      creature_data = prepare_creature_data(ctx.adventure, creatures)

      creature_names = creature_data.map { |c| "#{c[:name]} (init #{c[:initiative]})" }
      ctx.log.play_log!("warmaster", "Combat: #{creature_data.size} creature(s) ready",
                        parsed_response: { creature_count: creature_data.size, creatures: creature_names })

      { status: :awaiting_initiative, creature_data: creature_data }
    end

    def prepare_creature_data(adventure, creatures)
      creatures.map do |c|
        c.merge(initiative: roll_initiative_for_sheet_id(adventure, c[:actor_sheet_id]))
      end
    end

    def roll_initiative_for_sheet_id(adventure, actor_sheet_id)
      creature = adventure.adventure_actor_sheets.find_by(id: actor_sheet_id)
      return rand(1..20) unless creature

      dex_mod = ((creature.dexterity - 10).to_f / 2).floor
      feat_bonus = creature.feat_definitions.exists?(name: "Improved Initiative") ? 4 : 0
      rand(1..20) + dex_mod + feat_bonus
    end

    def creature_record(sheet, display_name)
      { name: display_name, actor_sheet_id: sheet.id }
    end

    private_class_method :spawn_from_manifest, :build_initiative_result,
                         :prepare_creature_data, :roll_initiative_for_sheet_id,
                         :creature_record, :pending_npc_combatants
  end
end
