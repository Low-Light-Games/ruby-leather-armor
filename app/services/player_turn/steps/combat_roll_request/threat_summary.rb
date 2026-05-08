# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatRollRequest
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
