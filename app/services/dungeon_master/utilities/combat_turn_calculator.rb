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
          ctx = combat_context.deep_stringify_keys
          return default_skip unless ctx["active"] == true

          turn_order = Array(ctx["turn_order"]).map(&:to_s)
          participants = Array(ctx["participants"]).map { |p| Combatant.from_context_hash(p) }
          by_name = participants.index_by(&:name)

          round = ctx["round"].to_i
          round = 1 if round < 1

          npcs = participants.select(&:npc?)
          # Combat ends only when every NPC is eliminated (dead/0 HP) or has left (flee/surrender).
          # Paralyzed, petrified, dazed, etc. are "cannot act this round", not encounter over.
          if npcs.all?(&:eliminated_from_encounter?)
            return {
              npc_turns: [],
              next_state: {
                "current_turn" => PLAYER_NAME,
                "round" => round,
                "active" => false
              }
            }
          end

          current_turn = ctx["current_turn"].presence || turn_order.first

          p_idx = turn_order.index(PLAYER_NAME)
          return missing_player_state(round) unless p_idx

          npc_turns = []

          return resolve_player_first_turn_handoff(turn_order, by_name, npc_turns, p_idx, current_turn, round) unless player_acted_this_round

          if player_just_acted?(current_turn)
            append_wrapped_round_after_player(turn_order, by_name, npc_turns, p_idx)
          else
            append_remaining_npcs_after_out_of_order_player_turn(turn_order, by_name, npc_turns, p_idx, current_turn)
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
            next_state: {
              "current_turn" => PLAYER_NAME,
              "round" => round,
              "active" => true
            }
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
            next_state: {
              "current_turn" => PLAYER_NAME,
              "round" => round + 1,
              "active" => true
            }
          }
        end

        def missing_player_state(round)
          {
            npc_turns: [],
            next_state: { "current_turn" => PLAYER_NAME, "round" => round, "active" => true }
          }
        end

        def append_npc!(by_name, name, npc_turns)
          c = by_name[name.to_s]
          return unless c&.npc?
          return unless c.can_act?

          npc_turns << c
        end
      end
    end
  end
end
