# frozen_string_literal: true

module PlayerTurn
  class Engine
    class PromptPhaseInput
      def initialize(player_input:)
        @player_input = player_input
      end

      def to_h
        { player_input: @player_input }
      end
    end
  end
end
