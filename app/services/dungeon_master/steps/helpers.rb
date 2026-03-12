# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Shared helper for all AI-calling pipeline steps.
    # Wraps the common timing, success-logging, and error-logging boilerplate
    # so each step only expresses what is unique to it.
    module Helpers
      private

      # Executes an AI call with automatic timing, success logging, and error logging.
      # The block must return [raw_response, parsed_response].
      # Always re-raises on error after logging — no silent fallbacks.
      def timed_ai_call(step_name, prompt_summary, request_body)
        t0  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil

        raw, parsed = yield
        @log.ai_log!(step_name, prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status,
                     request_body: request_body,
                     model_used:   @ai.last_model_used,
                     duration_ms:  elapsed_ms(t0),
                     usage:        @ai.last_usage)
        parsed

      rescue TokenBudgetExceededError, AiError => e
        @log.ai_log_error!(step_name, prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body,
                           status:       e.is_a?(TokenBudgetExceededError) ? "token_budget_exceeded" : "api_error",
                           model_used:   @ai.last_model_used,
                           duration_ms:  elapsed_ms(t0),
                           usage:        @ai.last_usage)
        raise
      end

      # Environment-aware error handler for non-AI rescue blocks.
      # In development/test: always re-raises after logging.
      # In production: logs and returns the fallback value.
      def pipeline_error!(step_name, error, fallback: nil)
        @log.dm_log!("[#{step_name}] ERROR: #{error.class} — #{error.message}")
        raise if Rails.env.local?
        fallback
      end

      def elapsed_ms(t0)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      end
    end
  end
end
