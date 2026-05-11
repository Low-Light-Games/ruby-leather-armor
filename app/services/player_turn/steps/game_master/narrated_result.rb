# frozen_string_literal: true

module PlayerTurn
  module Steps
    module GameMaster
      class NarratedResult
        def initialize(narrative:, adventure_complete:, player_death:)
          @narrative = narrative
          @adventure_complete = adventure_complete
          @player_death = player_death
        end

        def to_h
          {
            action: :narrated,
            narrative: @narrative,
            adventure_complete: @adventure_complete,
            player_death: @player_death,
            action_outcomes: [],
            world_turn_lines: []
          }
        end
      end
    end
  end
end
