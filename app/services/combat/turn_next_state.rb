# frozen_string_literal: true

module Combat
  class TurnNextState
    def initialize(round:, active:, current_turn: TurnCalculator::PLAYER_NAME)
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
