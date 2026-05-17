# frozen_string_literal: true

module PlayerTurn
  module Steps
    module SanityChecker
      class EvaluatorPromptPayload
        def initialize(system_prompt:, user_message:, model:, step:, reasoning_effort: nil)
          @system_prompt = system_prompt
          @user_message = user_message
          @model = model
          @step = step
          @reasoning_effort = reasoning_effort
        end

        def to_h
          {
            system_prompt:    @system_prompt,
            user_message:     @user_message,
            model:            @model,
            reasoning_effort: @reasoning_effort,
            meta:             { step: @step }
          }
        end
      end
    end
  end
end
