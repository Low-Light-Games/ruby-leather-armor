# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Pure code: after the player resolves an action, determines which NPCs act in world turn
    # and the next combat_context slice (current_turn, round, active).
    class CombatTurnCalculator
      PLAYER_NAME = "Player"

      class << self
        # @return [Hash] :npc_turns => Array<Combatant>, :next_state => Hash of string keys
        def call(combat_context:, player_acted_this_round: true)
          normalized_combat_context = combat_context.deep_stringify_keys
          return default_skip unless normalized_combat_context["active"] == true

          turn_order = Array(normalized_combat_context["turn_order"]).map(&:to_s)
          participants = Array(normalized_combat_context["participants"]).map { |participant| Combatant.from_context_hash(participant) }
          by_name = participants.index_by(&:name)

          round = normalized_combat_context["round"].to_i
          round = 1 if round < 1

          npcs = participants.select(&:npc?)
          # Combat ends only when every NPC is eliminated (dead/0 HP) or has left (flee/surrender).
          # Paralyzed, petrified, dazed, etc. are "cannot act this round", not encounter over.
          if npcs.all?(&:eliminated_from_encounter?)
            return {
              npc_turns: [],
              next_state: CombatTurnNextState.new(round: round, active: false).to_h
            }
          end

          current_turn = normalized_combat_context["current_turn"].presence || turn_order.first

          player_index = turn_order.index(PLAYER_NAME)
          return missing_player_state(round) unless player_index

          npc_turns = []

          return resolve_player_first_turn_handoff(turn_order, by_name, npc_turns, player_index, current_turn, round) unless player_acted_this_round

          if player_just_acted?(current_turn)
            append_wrapped_round_after_player(turn_order, by_name, npc_turns, player_index)
          else
            append_remaining_npcs_after_out_of_order_player_turn(turn_order, by_name, npc_turns, player_index, current_turn)
          end

          next_round_state(npc_turns, round)
        end

        private

        def default_skip
          { npc_turns: [], next_state: {} }
        end

        def player_just_acted?(current_turn)
          current_turn.to_s == PLAYER_NAME
        end

        def append_wrapped_round_after_player(turn_order, by_name, npc_turns, player_index)
          append_npc_range!(turn_order, by_name, npc_turns, (player_index + 1)...turn_order.length)
          append_npc_range!(turn_order, by_name, npc_turns, 0...player_index)
        end

        def append_remaining_npcs_after_out_of_order_player_turn(turn_order, by_name, npc_turns, player_index, current_turn)
          current_index = turn_order.index(current_turn.to_s)
          if current_index_before_player?(current_index, player_index)
            append_npc_range!(turn_order, by_name, npc_turns, current_index...player_index)
            append_npc_range!(turn_order, by_name, npc_turns, (player_index + 1)...turn_order.length)
          else
            append_wrapped_round_after_player(turn_order, by_name, npc_turns, player_index)
          end
        end

        def resolve_player_first_turn_handoff(turn_order, by_name, npc_turns, player_index, current_turn, round)
          current_index = turn_order.index(current_turn.to_s)
          append_npc_range!(turn_order, by_name, npc_turns, current_index...player_index) if current_index_before_player?(current_index, player_index)

          {
            npc_turns: npc_turns,
            next_state: CombatTurnNextState.new(round: round, active: true).to_h
          }
        end

        def current_index_before_player?(current_index, player_index)
          current_index && current_index < player_index
        end

        def append_npc_range!(turn_order, by_name, npc_turns, range)
          range.each { |index| append_npc!(by_name, turn_order[index], npc_turns) }
        end

        def next_round_state(npc_turns, round)
          {
            npc_turns: npc_turns,
            next_state: CombatTurnNextState.new(round: round + 1, active: true).to_h
          }
        end

        def missing_player_state(round)
          {
            npc_turns: [],
            next_state: CombatTurnNextState.new(round: round, active: true).to_h
          }
        end

        def append_npc!(by_name, name, npc_turns)
          combatant = by_name[name.to_s]
          return unless combatant&.npc?

          return unless combatant.can_act?

          npc_turns << combatant
        end
      end
    end
  end
end
