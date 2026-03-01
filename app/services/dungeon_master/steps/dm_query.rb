# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Fast-path step for DM queries.
    # Answers the player's question using current game state and rules
    # without advancing the scene or triggering mechanics.
    module DmQuery
      private

      def run_dm_query(sanitized_input)
        raw = nil
        prompt_summary = "DM Query: \"#{@log.truncate(sanitized_input)}\""

        micro_contexts = {
          traversal: @adventure.traversal_context,
          combat: @adventure.combat_context,
          social: @adventure.social_context
        }

        system_prompt = PromptRenderer.render("dm_query",
          story_title: @adventure.story.title,
          story_summary: @adventure.story_summary,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          guidance: Rules.guidance_for("dm_query"))

        request_body = { system_prompt: system_prompt, user_message: sanitized_input }
        raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                        max_tokens: @config.token_budget_for("dm_query"), step_name: "dm_query",
                        model: @config.model_for("dm_query"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("dm_query", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        { answer: parsed["answer"] || "The DM ponders your question..." }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("dm_query", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("dm_query", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end
    end
  end
end
