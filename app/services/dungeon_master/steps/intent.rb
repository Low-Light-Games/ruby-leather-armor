# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Pure intent interpretation.
    # Restates what the player wants to do — nothing else.
    # No context classification, no mechanics decision, no rules.
    module Intent
      private

      def run_intent(sanitized_input)
        raw = nil
        prompt_summary = "Intent: \"#{@log.truncate(sanitized_input)}\""
        system_prompt = PromptRenderer.render("intent")
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                        max_tokens: @config.token_budget_for("intent"), step_name: "intent",
                        model: @config.model_for("intent"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("intent", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        parsed["intention"] || sanitized_input
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("intent", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("intent", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end
    end
  end
end
