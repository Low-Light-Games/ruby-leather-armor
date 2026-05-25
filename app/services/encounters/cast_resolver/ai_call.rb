# frozen_string_literal: true

module Encounters
  class CastResolver
    class AiCall
      AI_STEP_NAME = "cast_resolver"

      def self.run(adventure:, intent_text:, ai:, log:, config:, scene_retrieval: nil)
        new(adventure: adventure, intent_text: intent_text, ai: ai, log: log,
            config: config, scene_retrieval: scene_retrieval).run
      end

      # Builds an evaluator fan_out payload for CastResolver — system_prompt
      # rendered and meta tagged, but no AI call. The caller (fan_out
      # transport) makes the actual HTTP request and the result is fed back
      # through parse_ai_entries.
      def self.evaluator_prompt(adventure:, intent_text:, ai:, log:, config:, scene_retrieval: nil)
        new(adventure: adventure, intent_text: intent_text, ai: ai, log: log,
            config: config, scene_retrieval: scene_retrieval).evaluator_prompt
      end

      # Extracts the [{name, type, count}] entries from a parsed AI response.
      def self.parse_ai_entries(parsed_response)
        Array(parsed_response.is_a?(Hash) ? parsed_response["cast"] : nil).select { |entry| entry.is_a?(Hash) }
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

        self.class.parse_ai_entries(parsed)
      end

      def evaluator_prompt
        scene_retrieval = @scene_retrieval || retrieve_scene
        system_prompt = Ai::PromptRenderer.render(
          AI_STEP_NAME,
          intent: @intent_text,
          current_location_name: @adventure.current_location&.name,
          scene_retrieval: scene_retrieval,
        )

        {
          system_prompt:    system_prompt,
          user_message:     @intent_text,
          model:            @config.model_for(AI_STEP_NAME),
          reasoning_effort: @config.reasoning_effort_for(AI_STEP_NAME),
          meta:             { step: AI_STEP_NAME }
        }
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
