# frozen_string_literal: true

module Encounters
  class CastResolver
    class AiCall
      AI_STEP_NAME = "cast_resolver"

      def self.run(adventure:, intent_text:, ai:, log:, config:, scene_retrieval: nil)
        new(adventure: adventure, intent_text: intent_text, ai: ai, log: log,
            config: config, scene_retrieval: scene_retrieval).run
      end

      def initialize(adventure:, intent_text:, ai:, log:, config:, scene_retrieval: nil)
        @adventure       = adventure
        @intent_text     = intent_text
        @ai              = ai
        @log             = log
        @config          = config
        @scene_retrieval = scene_retrieval
      end

      # @return [Array<Hash>] each hash has "name", "type", optional "count"
      def run
        scene_retrieval = @scene_retrieval || retrieve_scene
        system_prompt = Ai::PromptRenderer.render(
          AI_STEP_NAME,
          intent: @intent_text,
          current_location_name: @adventure.current_location&.name,
          scene_retrieval: scene_retrieval,
        )

        prompt_summary = "CastResolver: \"#{@log.truncate(@intent_text)}\""
        request_body   = { system_prompt: system_prompt, user_message: @intent_text }

        parsed = @log.timed_chat_call(AI_STEP_NAME, prompt_summary, ai: @ai, request_body: request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message:  @intent_text,
            step_name:     AI_STEP_NAME,
            model:         @config.model_for(AI_STEP_NAME),
            reasoning_effort: @config.reasoning_effort_for(AI_STEP_NAME),
          )
          [raw, @ai.parse_json(raw)]
        end

        Array(parsed.is_a?(Hash) ? parsed["cast"] : nil).select { |entry| entry.is_a?(Hash) }
      end

      private

      def retrieve_scene
        SceneRetrieval::ForResolution.call(
          adventure:   @adventure,
          intent_text: @intent_text,
          ai:          @ai,
          log:         @log,
        )
      end
    end
  end
end
