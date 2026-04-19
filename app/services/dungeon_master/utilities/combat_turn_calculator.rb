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
          unless p_idx
            return {
              npc_turns: [],
              next_state: { "current_turn" => PLAYER_NAME, "round" => round, "active" => true }
            }
          end

          npc_turns = []

          if current_turn.to_s == PLAYER_NAME
            # Normal case: player just completed their turn.
            # Run NPCs after the player in the current round, then wrap to the NPCs before
            # the player (they act first in the next round).
            ((p_idx + 1)...turn_order.length).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
            (0...p_idx).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
          elsif player_acted_this_round
            # Player acted while an NPC held the turn (e.g. after initiative setup placed a
            # high-initiative enemy first). Run the NPCs that should have acted before the
            # player, then the NPCs after the player — completing the full round.
            current_idx = turn_order.index(current_turn.to_s)

            if current_idx && current_idx < p_idx
              # Pre-player NPCs: from the current holder up to (not including) the player.
              (current_idx...p_idx).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
              # Post-player NPCs: remainder of this round (no wrap — pre-player already handled).
              ((p_idx + 1)...turn_order.length).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
            else
              # current_turn not found in order or is already past the player — fall back to
              # the normal post-player + wrap path.
              ((p_idx + 1)...turn_order.length).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
              (0...p_idx).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
            end
          else
            current_idx = turn_order.index(current_turn.to_s)
            if current_idx && current_idx < p_idx
              (current_idx...p_idx).each { |i| append_npc!(by_name, turn_order[i], npc_turns) }
            end

            return {
              npc_turns: npc_turns,
              next_state: {
                "current_turn" => PLAYER_NAME,
                "round" => round,
                "active" => true
              }
            }
          end

          {
            npc_turns: npc_turns,
            next_state: {
              "current_turn" => PLAYER_NAME,
              "round" => round + 1,
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
