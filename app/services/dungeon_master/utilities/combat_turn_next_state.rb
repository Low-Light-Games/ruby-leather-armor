# frozen_string_literal: true

module DungeonMaster
  module Utilities
    class CombatTurnNextState
      def initialize(round:, active:, current_turn: CombatTurnCalculator::PLAYER_NAME)
        @round = round.to_i
        @active = active == true
        @current_turn = current_turn.to_s
      end

      def to_h
        {
          "current_turn" => @current_turn,
          "round" => @round,
          "active" => @active
        }
      end
    end
  end
end
