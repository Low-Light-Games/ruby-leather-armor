# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 2: Interpret the player's intention.
    # Determines whether mechanics are needed, which contexts are affected,
    # and which rules to fetch.
    module Intent
      private

      def run_intent(sanitized_input)
        raw = nil
        prompt_summary = "Intent: \"#{@log.truncate(sanitized_input)}\""
        manifest = Rules.manifest

        system_prompt = PromptRenderer.render("intent",
          contexts: PromptHelpers.build_micro_contexts_block(@adventure),
          manifest_text: PromptHelpers.format_manifest(manifest))
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                        max_tokens: @config.token_budget_for("intent"), step_name: "intent",
                        model: @config.model_for("intent"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("intent", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          intention: parsed["intention"] || sanitized_input,
          needs_mechanics: parsed["needs_mechanics"] == true,
          affected_contexts: Array(parsed["affected_contexts"]).map(&:to_s) & %w[combat traversal social],
          primary_context: parsed["primary_context"]&.to_s,
          rules_needed: Array(parsed["rules_needed"]).map(&:to_s),
          transition: parsed["transition"],
          macro_significant: parsed["macro_significant"] == true
        }
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
