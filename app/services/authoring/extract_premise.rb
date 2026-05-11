# frozen_string_literal: true

module Authoring
  class ExtractPremise
    EXTRACTOR_MODEL_KEY = "extract_from_premise"

    def self.call(story:, user: nil, ai: nil, log: nil, config: nil)
      new(story: story, user: user, ai: ai, log: log, config: config).call
    end

    def initialize(story:, user: nil, ai: nil, log: nil, config: nil)
      @story  = story
      @user   = user
      @config = config || DmConfig.instance
      @ai     = ai || Ai::Client.new(@config)
      @log    = log || Ai::Logging.new(adventure: nil, user: @user, dm_service: "standard")
    end

    def call
      return [] if @story.premise.to_s.strip.empty?

      result = run_extraction_call
      return [] if result.nil?

      Array(result["facts"]).select { |f| f.is_a?(Hash) }
    rescue StandardError => e
      @log.report_error(e, context: error_context)
      @log.play_log!(
        "extract_from_premise_failure",
        "ExtractPremise failed: #{e.class}",
        parsed_response: { error: e.message.to_s.truncate(500) },
      )
      []
    end

    private

    def run_extraction_call
      system_prompt = Ai::PromptRenderer.render(
        "authoring/extract_premise",
        premise:         @story.premise,
        opening_message: @story.opening_message,
        schema_json:     Ai::PromptRenderer.load_schema("authoring/extract_premise"),
      )

      prompt_summary = "ExtractPremise — story ##{@story.id}"

      @log.timed_chat_call(EXTRACTOR_MODEL_KEY, prompt_summary, ai: @ai) do
        raw = @ai.chat(
          system_prompt: system_prompt,
          user_message:  "Extract durable narrative facts from this story.",
          step_name:     EXTRACTOR_MODEL_KEY,
          model:         @config.model_for(EXTRACTOR_MODEL_KEY),
        )
        [raw, @ai.parse_json(raw)]
      end
    end

    def error_context
      Lore::ErrorContext.new(
        step:         "extract_from_premise",
        adventure_id: nil,
        loop_id:      nil,
        source:       "extract_from_premise",
      )
    end
  end
end
