# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 1: Sanitize + classify player input.
    # Scores danger (prompt injection / meta-gaming) and categorises the action.
    module Triage
      private

      def run_triage(player_input)
        raw = nil
        prompt_summary = "Triage: \"#{@log.truncate(player_input)}\""
        system_prompt = PromptRenderer.render("triage")
        request_body = { system_prompt: system_prompt, user_message: player_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: player_input,
                        max_tokens: @config.token_budget_for("triage"), step_name: "triage",
                        model: @config.model_for("triage"))
        parsed = @ai.parse_json(raw, fallback_as: :sanitization)
        @log.ai_log!("triage", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          danger_score: parsed["danger_score"].to_i,
          sanitized_input: parsed["sanitized_input"] || player_input,
          reason: parsed["reason"],
          category: normalize_category(parsed["category"])
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("triage", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("triage", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end
    end
  end
end
