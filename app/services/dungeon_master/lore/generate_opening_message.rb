# frozen_string_literal: true

module DungeonMaster
  module Lore
    # JIT generator for stories created before opening_message was a
    # required field. Reads `Story.premise` and writes a short opening
    # scene back to `Story.opening_message`. Called from
    # `Adventures::Bootstrap` only when the story has a blank opening.
    class GenerateOpeningMessage
      MODEL_KEY = "generate_opening_message"

      def self.call(story:, user: nil, ai: nil, log: nil, config: nil)
        new(story: story, user: user, ai: ai, log: log, config: config).call
      end

      def initialize(story:, user: nil, ai: nil, log: nil, config: nil)
        @story  = story
        @user   = user
        @config = config || DmConfig.instance
        @ai     = ai || AiClient.new(@config)
        @log    = log || Logging.new(adventure: nil, user: @user, dm_service: "standard")
      end

      def call
        result = run_generation_call
        opening = result&.dig("opening_message").to_s.strip
        raise AiError, "Empty opening_message from AI" if opening.empty?

        @story.update!(opening_message: opening)
        opening
      end

      private

      def run_generation_call
        system_prompt = PromptRenderer.render(
          "generate_opening_message",
          premise: @story.premise,
        )

        prompt_summary = "GenerateOpeningMessage — story ##{@story.id}"

        @log.timed_chat_call(MODEL_KEY, prompt_summary, ai: @ai) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message:  "Write the opening scene for this adventure.",
            max_tokens:    @config.token_budget_for(MODEL_KEY),
            step_name:     MODEL_KEY,
            model:         @config.model_for(MODEL_KEY),
          )
          [raw, @ai.parse_json(raw)]
        end
      end
    end
  end
end
