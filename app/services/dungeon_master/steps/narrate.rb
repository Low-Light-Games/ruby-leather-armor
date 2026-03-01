# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 5: Narrate.
    # Produces player-facing narrative prose from the mechanical outcome.
    module Narrate
      private

      def run_narrate(outcome)
        raw = nil
        prompt_summary = "Narrate"

        micro_contexts = {
          traversal: @adventure.traversal_context,
          combat: @adventure.combat_context,
          social: @adventure.social_context
        }

        system_prompt = PromptRenderer.render("narrate",
          story_title: @adventure.story.title,
          story_premise: @adventure.story.premise,
          story_summary: @adventure.story_summary,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          outcome: outcome,
          pacing_text: PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure))

        user_msg = outcome || "Narrate the current scene."
        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                        max_tokens: @config.token_budget_for("narrate"), step_name: "narrate",
                        model: @config.model_for("narrate"))

        parsed = @ai.parse_json(raw, fallback_as: :dm_response)
        @log.ai_log!("narrate", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          narrative: parsed["narrative"] || "The Dungeon Master pauses thoughtfully...",
          adventure_complete: parsed["adventure_complete"] == true
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("narrate", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("narrate", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end
    end
  end
end
