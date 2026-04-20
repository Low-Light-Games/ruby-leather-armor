# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    class TurnState
      attr_reader :round, :holder

      def initialize(round:, holder:)
        @round = round.to_i
        @holder = holder.to_s
      end

      def to_h
        {
          "round" => round,
          "holder" => holder,
          "standard_available" => true,
          "move_available" => true,
          "swift_available" => true,
          "full_round_claimed" => false
        }
      end
    end
  end
end
