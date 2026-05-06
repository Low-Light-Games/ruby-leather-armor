# frozen_string_literal: true

module DungeonMaster
  module Steps
    module GameMaster
      class PlanLogPayload
        def initialize(reasoning:, narrative_chars:, adventure_ended:, player_dead:, tool_calls:)
          @reasoning = reasoning
          @narrative_chars = narrative_chars
          @adventure_ended = adventure_ended
          @player_dead = player_dead
          @tool_calls = tool_calls
        end

        def to_h
          {
            reasoning: @reasoning,
            narrative_chars: @narrative_chars,
            adventure_ended: @adventure_ended,
            player_dead: @player_dead,
            tool_calls: @tool_calls
          }
        end
      end
    end
  end
end
