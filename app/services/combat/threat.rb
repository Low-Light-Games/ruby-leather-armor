# frozen_string_literal: true

module Combat
  # An attacker (Combat::Position) whose reach covers a particular
  # square — produced by Combat::Rules.aoo_threats_against and consumed
  # by the AoO leg of Combat::PlayerActionResolver.
  class Threat
    attr_reader :position, :reach_squares

    def initialize(position:, reach_squares:)
      @position = position
      @reach_squares = reach_squares
    end
  end
end
