# frozen_string_literal: true

module Combat
  module Resolvers
    # End-of-player-turn resolution: spends what's left of the player's
    # action economy, fans out the NPC initiative band via Combat::NpcTurn
    # (each NPC walks its ProgrammedBehavior — attack at range, approach
    # if out of reach, flee under morale), and refreshes the player's
    # economy for the next round. The wire-protocol kind stays
    # 'end_turn' since the frontend payload union depends on it.
    module EndPlayerTurn
      private

      def resolve_end_turn
        previous_round = (@adventure.combat_context || {})['round'].to_i
        npc_events = run_npc_turns
        next_round = advance_round_and_refresh_economy!

        payload = end_turn_payload(next_round, npc_events)
        log_action_event!(payload)
        enqueue_combat_narrator!(round: previous_round, npc_events: npc_events)
        { status: :resolved, result: payload }
      end

      def enqueue_combat_narrator!(round:, npc_events:)
        config = DmConfig.instance
        return unless config.combat_narrator_enabled?

        return if npc_events.empty?

        CombatNarratorJob.perform_later(@adventure.id, round, npc_events.map(&:deep_stringify_keys))
      rescue StandardError => e
        Rails.logger.warn("[EndPlayerTurn] failed to enqueue CombatNarratorJob: #{e.message}")
      end

      def run_npc_turns
        creatures = active_npcs_in_initiative_order
        creatures.flat_map { |creature| Combat::NpcTurn.call(creature: creature, adventure: @adventure, target_sheet: @sheet) }
      rescue StandardError => e
        Rails.logger.warn("[EndPlayerTurn] NPC turn engine failed: #{e.message}")
        [{ kind: 'npc_skip', creature_id: nil, creature_name: '(engine error)', message: e.message }]
      end

      def active_npcs_in_initiative_order
        ids = ordered_npc_creature_sheet_ids(@adventure.combat_context || {})
        return [] if ids.empty?

        # Preserve the initiative order encoded in `ids` — DB row id is
        # creation order, not initiative. .where(id: ids) returns rows in
        # arbitrary order, so re-sort by index_of(creature.id) and drop
        # any that are already down.
        by_id = @adventure.creature_sheets.where(id: ids).where('hp > 0').index_by(&:id)
        ids.filter_map { |id| by_id[id] }
      end

      def ordered_npc_creature_sheet_ids(ctx)
        participants = Array(ctx['participants'])
        names_to_ids = participants_name_to_id(participants)
        ordered_names = Array(ctx['turn_order'])
                        .reject { |n| n.to_s == Combat::PlayerActionResolver::PLAYER_NAME }
        ids = ordered_names.filter_map { |n| names_to_ids[n.to_s] }
        return ids unless ids.empty?

        participants.filter_map { |p| p['creature_sheet_id']&.to_i }
      end

      def participants_name_to_id(participants)
        participants.each_with_object({}) do |p, acc|
          sid = p['creature_sheet_id']
          acc[p['name'].to_s] = sid.to_i if sid
        end
      end

      def advance_round_and_refresh_economy!
        next_round = nil
        @adventure.with_lock do
          ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
          next_round = ctx['round'].to_i.then { |r| [r, 1].max + 1 }
          player = Combat::PlayerActionResolver::PLAYER_NAME
          ctx['round'] = next_round
          ctx['current_turn'] = player
          ctx['action_economy'] = DungeonMaster::Battlefield::ActionEconomy
                                  .build_for_turn_holder(player, combat_ctx: ctx)
          @adventure.update!(combat_context: ctx)
        end

        next_round
      end

      def end_turn_payload(next_round, npc_events)
        npc_hits = npc_events.count do |e|
          e[:kind] == 'npc_attack' && e.dig(:outcome, 'hit') == true
        end

        {
          kind: 'end_turn',
          round_advanced_to: next_round,
          npc_events: npc_events,
          message: "Turn ended. #{npc_events.length} NPC action(s), #{npc_hits} hit(s). Round #{next_round} begins."
        }
      end
    end
  end
end
