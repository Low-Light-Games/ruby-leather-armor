# frozen_string_literal: true

module Combat
  class Threat
    attr_reader :position, :reach_squares

    def initialize(position:, reach_squares:)
      @position = position
      @reach_squares = reach_squares
    end
  end
end
