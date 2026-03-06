# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Gate: parallel Sanitize + Classify.
    #
    # Sanitize — scores danger (prompt injection / meta-gaming). Can kill the pipeline.
    # Classify — categorises the player's action into a game domain.
    #
    # These two steps have zero dependency on each other and run in parallel.
    module Triage
      private

      def run_sanitize(player_input)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Sanitize: \"#{@log.truncate(player_input)}\""
        system_prompt = PromptRenderer.render("sanitize")
        request_body = { system_prompt: system_prompt, user_message: player_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: player_input,
                        max_tokens: @config.token_budget_for("sanitize"), step_name: "sanitize",
                        model: @config.model_for("sanitize"))
        parsed = @ai.parse_json(raw, fallback_as: :sanitization)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("sanitize", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms, usage: @ai.last_usage)

        {
          danger_score: parsed["danger_score"].to_i,
          sanitized_input: parsed["sanitized_input"] || player_input,
          reason: parsed["reason"]
        }
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("sanitize", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms, usage: @ai.last_usage)
        raise
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("sanitize", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms, usage: @ai.last_usage)
        raise
      end

      def run_classify(player_input)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Classify: \"#{@log.truncate(player_input)}\""
        system_prompt = PromptRenderer.render("classify")
        request_body = { system_prompt: system_prompt, user_message: player_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: player_input,
                        max_tokens: @config.token_budget_for("classify"), step_name: "classify",
                        model: @config.model_for("classify"))
        parsed = @ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("classify", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms, usage: @ai.last_usage)

        {
          category: normalize_category(parsed["category"])
        }
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("classify", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms, usage: @ai.last_usage)
        raise
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("classify", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms, usage: @ai.last_usage)
        raise
      end
    end
  end
end
