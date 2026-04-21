# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    class PromptPhaseInput
      def initialize(player_input:, prompt_mode:)
        @player_input = player_input
        @prompt_mode = prompt_mode
      end

      def to_h
        {
          player_input: @player_input,
          prompt_mode: @prompt_mode
        }
      end
    end
  end
end
