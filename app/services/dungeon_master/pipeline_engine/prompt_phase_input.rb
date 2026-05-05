# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
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
