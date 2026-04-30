# frozen_string_literal: true

module DungeonMaster
  module Steps
    module CombatRollRequest
      # Per-threat row sent to the combat roll-request prompt — name +
      # current grid coordinates + Chebyshev distance to the player.
      # Wraps a Combat::Threat for the prompt-context payload so the
      # builder doesn't restate the field set every call.
      class ThreatSummary
        # @param threat [Combat::Threat]
        # @param player_pos [Combat::Position]
        def initialize(threat:, player_pos:)
          @threat = threat
          @player_pos = player_pos
        end

        def to_h
          position = @threat.position
          {
            name: position.label,
            x: position.x.to_i,
            y: position.y.to_i,
            distance_squares: position.distance_to(@player_pos)
          }
        end
      end
    end
  end
end
