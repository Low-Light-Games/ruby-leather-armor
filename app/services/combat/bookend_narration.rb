# frozen_string_literal: true

module Combat
  class BookendNarration
    STEP_NAME = "combat_bookend"

    def initialize(adventure:, config:, log:)
      @adventure = adventure
      @config = config
      @log = log
      @ai = Ai::Client.new(config)
    end

    def narrate_combat_end(reason:)
      combat_log = recent_combat_messages
      return nil if combat_log.blank?

      system_prompt = Ai::PromptRenderer.render("combat_bookend",
        reason: reason,
        combat_log: combat_log)

      prompt_summary = "CombatBookend (#{reason}): adventure ##{@adventure.id}"
      request_body = { system_prompt: system_prompt, user_message: reason }

      parsed = @log.timed_chat_call(STEP_NAME, prompt_summary, ai: @ai, request_body: request_body) do
        raw = @ai.chat(
          system_prompt: system_prompt,
          user_message: reason,
          step_name: STEP_NAME,
          model: @config.model_for(STEP_NAME),
          reasoning_effort: @config.reasoning_effort_for(STEP_NAME)
        )
        [raw, @ai.parse_json(raw)]
      end

      parsed["narration"].to_s.presence
    rescue Ai::Error => e
      ApplicationErrorReporter.notify(e, context: {
        source: "combat_bookend_narration",
        adventure_id: @adventure.id,
        reason: reason
      })
      nil
    end

    private

    def recent_combat_messages
      @adventure.adventure_messages
        .combat_activity
        .newest_first
        .limit(20)
        .pluck(:content)
        .reverse
        .join("\n")
    end
  end
end
