# frozen_string_literal: true

module Authoring
  class AuthorStoryNpcSheet
    MODEL_KEY    = "creature_generation"
    TEMPLATE_KEY = "authoring/creature_generation"
    DEFAULT_PARTY_LEVEL = 4

    def self.call(story_npc:, user: nil, ai: nil, log: nil, config: nil)
      new(story_npc: story_npc, user: user, ai: ai, log: log, config: config).call
    end

    def initialize(story_npc:, user: nil, ai: nil, log: nil, config: nil)
      @story_npc = story_npc
      @user      = user
      @config    = config || DmConfig.instance
      @ai        = ai || Ai::Client.new(@config)
      @log       = log || Ai::Logging.new(adventure: nil, user: @user, dm_service: "standard")
    end

    # @return [Hash]
    def call
      raw_attrs = run_generation_call
      BestiaryEntryDraft.new(raw_attrs, story_npc: @story_npc).to_bestiary_attrs
    end

    private

    def run_generation_call
      system_prompt, user_msg = Ai::PromptRenderer.render_with_user_message(
        TEMPLATE_KEY,
        creature_name: @story_npc.name,
        party_level:   DEFAULT_PARTY_LEVEL,
      )

      prompt_summary = "AuthorStoryNpcSheet — story_npc ##{@story_npc.id} (#{@story_npc.name})"

      result = @log.timed_chat_call(MODEL_KEY, prompt_summary, ai: @ai) do
        raw = @ai.chat(
          system_prompt: system_prompt,
          user_message:  user_msg,
          step_name:     MODEL_KEY,
          model:         @config.model_for(MODEL_KEY),
        )
        [raw, @ai.parse_json(raw)]
      end

      entries = result.is_a?(Array) ? result : [result]
      entries.first || {}
    end
  end
end
