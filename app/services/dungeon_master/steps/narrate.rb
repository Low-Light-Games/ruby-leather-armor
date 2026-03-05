# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 5: Narrate.
    # Produces player-facing narrative prose from the mechanical outcome.
    module Narrate
      private

      def run_narrate(outcome, player_action: nil, intent: nil, dm_brief: nil)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Narrate"

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        story_context = narrate_story_context(dm_brief)
        time_ctx = @adventure.time_context || {}

        system_prompt = PromptRenderer.render("narrate",
          story_title: @adventure.story.title,
          story_context: story_context,
          story_summary: @adventure.story_summary,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          time_context: time_ctx,
          outcome: outcome,
          player_action: player_action,
          player_intent: intent&.dig(:intention),
          pacing_text: PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure))

        user_msg = outcome || player_action
        raise AiError, "Narrate step reached without an outcome or player action — nothing to narrate" unless user_msg
        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                        max_tokens: @config.token_budget_for("narrate"), step_name: "narrate",
                        model: @config.model_for("narrate"))

        parsed = @ai.parse_json(raw, fallback_as: :dm_response)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("narrate", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms)

        raise AiError, "Narrate step returned no narrative — model produced: #{raw.to_s.truncate(200)}" unless parsed["narrative"].present?

        {
          narrative: parsed["narrative"],
          adventure_complete: parsed["adventure_complete"] == true
        }
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("narrate", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms)
        raise
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("narrate", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms)
        raise
      end

      def narrate_story_context(dm_brief)
        hook = @adventure.story.hook.presence || @adventure.story.preview
        enriched_world = @adventure.enriched_world || {}
        atmosphere = enriched_world["atmosphere"]

        parts = []
        parts << "Hook: #{hook}"
        parts << "Atmosphere: #{atmosphere}" if atmosphere.present?
        parts << "DM Brief (follow these instructions carefully): #{dm_brief}" if dm_brief.present?

        parts.join("\n")
      end
    end
  end
end
