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
        attempts = 0
        t0  = nil
        raw = nil

        begin
          attempts += 1
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
        rescue Ai::TokenBudgetExceededError, Ai::Error => e
          if attempts == 1 && parse_error_retryable?(e)
            log_parse_retry!(step_name, prompt_summary)
            retry
          end

          @log.ai_log_error!(step_name, prompt_summary, e,
                             raw_response: raw || @ai.last_failed_raw_response,
                             request_body: request_body,
                             status:       e.is_a?(Ai::TokenBudgetExceededError) ? "token_budget_exceeded" : "api_error",
                             model_used:   @ai.last_model_used,
                             duration_ms:  elapsed_ms(t0),
                             usage:        @ai.last_usage)
          raise
        end
      end

      def parse_error_retryable?(exception)
        return false if exception.is_a?(Ai::TokenBudgetExceededError)

        @ai.last_parse_status == "parse_error"
      end

      def log_parse_retry!(step_name, prompt_summary)
        @log.play_log!(
          "parse_retry",
          "#{step_name}: parse_error on attempt 1, retrying once",
          parsed_response: { step: step_name, prompt_summary: prompt_summary.to_s.truncate(160) }
        )
      end

      # Error handler for non-AI rescue blocks.
      # Always logs and re-raises — no silent fallbacks, no env gating.
      def pipeline_error!(step_name, error)
        @log.log!(:error, "[#{step_name}] #{error.class}: #{error.message}")
        raise
      end

      def elapsed_ms(t0)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      end

      # Sends a live status message to the player's UI via ActionCable.
      # No-op when no progress callback is wired (e.g. in tests).
      def broadcast_progress(message)
        @on_progress&.call(message)
      end

      def combat_active?
        @adventure.combat_active?
      end
    end
  end
end
