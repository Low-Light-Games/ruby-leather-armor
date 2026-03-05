# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: PlayerInterpreter (pure intent interpretation).
    # Restates what the player wants to do — nothing else.
    # No context classification, no mechanics decision, no rules.
    module PlayerInterpreter
      private

      def run_player_interpreter(sanitized_input)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "PlayerInterpreter: \"#{@log.truncate(sanitized_input)}\""
        system_prompt = PromptRenderer.render("player_interpreter")
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                        max_tokens: @config.token_budget_for("player_interpreter"), step_name: "player_interpreter",
                        model: @config.model_for("player_interpreter"))
        parsed = @ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("player_interpreter", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms)

        parsed["intention"] || sanitized_input
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("player_interpreter", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms)
        raise
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("player_interpreter", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms)
        raise
      end
    end
  end
end
