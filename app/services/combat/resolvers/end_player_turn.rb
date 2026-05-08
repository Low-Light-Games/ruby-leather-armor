# frozen_string_literal: true

module Combat
  module Resolvers
    module EndPlayerTurn
      ROUND_DURATION_HOURS = 6.0 / 3600

      private

      def resolve_end_turn
        npc_events = run_npc_turns
        next_round = advance_round_and_refresh_economy!
        advance_game_clock_one_round!

        payload = end_turn_payload(next_round, npc_events)
        log_action_event!(payload)
        { status: :resolved, result: payload }
      end

      def advance_game_clock_one_round!
        Adventures::GameClock.advance_clock!(@adventure, ROUND_DURATION_HOURS)
      rescue StandardError => e
        Rails.logger.warn("[EndPlayerTurn] failed to tick GameClock: #{e.message}")
      end

      def run_npc_turns
        creatures = active_npcs_in_initiative_order
        creatures.flat_map do |creature|
          events = Combat::NpcTurn.call(creature: creature, adventure: @adventure, target_sheet: @sheet)
          events.each { |event| Combat::EventLog.write_npc_event!(adventure: @adventure, event: event, user: @user) }
          Combat::ContextSync.refresh_participants!(@adventure, @sheet)
          events
        end
      rescue StandardError => e
        Rails.logger.warn("[EndPlayerTurn] NPC turn engine failed: #{e.message}")
        [{ kind: 'npc_skip', creature_id: nil, creature_name: '(engine error)', message: e.message }]
      end

      def active_npcs_in_initiative_order
        ids = ordered_npc_creature_sheet_ids(@adventure.combat_context || {})
        return [] if ids.empty?

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
          ctx['action_economy'] = Battlefield::ActionEconomy
                                  .build_for_turn_holder(player, combat_ctx: ctx)
          @adventure.update!(combat_context: ctx)
        end

        next_round
      end

      def end_turn_payload(next_round, npc_events)
        Combat::Resolvers::EndTurnSummary.new(next_round: next_round, npc_events: npc_events).to_h
      end
    end
  end
end
