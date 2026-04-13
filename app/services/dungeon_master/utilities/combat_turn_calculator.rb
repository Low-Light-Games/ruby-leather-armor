# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Pure code: after the player resolves an action, determines which NPCs act in world turn
    # and the next combat_context slice (current_turn, round, active).
    class CombatTurnCalculator
      PLAYER_NAME = "Player"

      class << self
        # @return [Hash] :npc_turns => Array<Combatant>, :next_state => Hash of string keys
        def call(combat_context:, adventure: nil)
          ctx = combat_context.deep_stringify_keys
          return default_skip unless ctx["active"] == true

          turn_order = Array(ctx["turn_order"]).map(&:to_s)
          participants = Array(ctx["participants"]).map { |p| Combatant.from_context_hash(p) }
          by_name = participants.index_by(&:name)

          round = ctx["round"].to_i
          round = 1 if round < 1

          npcs = participants.select(&:npc?)
          if npcs.all? { |n| n.defeated? || !n.can_act? }
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
          # World turn runs immediately after the player's action; expect player's turn.
          unless current_turn.to_s == PLAYER_NAME
            return {
              npc_turns: [],
              next_state: {
                "current_turn" => current_turn,
                "round" => round,
                "active" => true
              }
            }
          end

          p_idx = turn_order.index(PLAYER_NAME)
          unless p_idx
            return {
              npc_turns: [],
              next_state: { "current_turn" => PLAYER_NAME, "round" => round, "active" => true }
            }
          end

          npc_turns = []
          if p_idx < turn_order.length - 1
            ((p_idx + 1)...turn_order.length).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
            new_round = round + 1
            (0...p_idx).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
          else
            new_round = round + 1
            (0...p_idx).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
          end

          {
            npc_turns: npc_turns,
            next_state: {
              "current_turn" => PLAYER_NAME,
              "round" => new_round,
              "active" => true
            }
          }
        end

        private

        def default_skip
          { npc_turns: [], next_state: {} }
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
