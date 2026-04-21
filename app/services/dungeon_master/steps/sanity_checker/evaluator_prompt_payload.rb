# frozen_string_literal: true

module DungeonMaster
  module Steps
    module SanityChecker
      class EvaluatorPromptPayload
        def initialize(system_prompt:, user_message:, model:, max_tokens:, step:)
          @system_prompt = system_prompt
          @user_message = user_message
          @model = model
          @max_tokens = max_tokens
          @step = step
        end

        def to_h
          {
            system_prompt: @system_prompt,
            user_message: @user_message,
            model: @model,
            max_tokens: @max_tokens,
            meta: { step: @step }
          }
        end
      end
    end
  end
end
