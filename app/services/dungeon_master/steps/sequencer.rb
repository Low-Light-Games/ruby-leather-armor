# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Compound action detection.
    # Analyzes player input for multiple sequential actions and returns
    # an ordered array of action texts. Single actions return a one-element
    # array. Skipped entirely when the action_queue toggle is off.
    module Sequencer
      private

      def run_sequencer(sanitized_input)
        unless @config.get("action_queue")
          return [sanitized_input]
        end

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Sequencer: \"#{@log.truncate(sanitized_input)}\""
        system_prompt = PromptRenderer.render("sequencer")
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                        max_tokens: @config.token_budget_for("sequencer"), step_name: "sequencer",
                        model: @config.model_for("sequencer"))
        parsed = @ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("sequencer", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms, usage: @ai.last_usage)

        actions = Array(parsed["actions"]).map(&:strip).reject(&:blank?)
        actions = [sanitized_input] if actions.empty?

        if actions.size > 1
          @log.dm_log!("Sequencer detected #{actions.size} sequential actions: #{actions.inspect}")
        end

        actions
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("sequencer", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms, usage: @ai.last_usage)
        [sanitized_input]
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("sequencer", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms, usage: @ai.last_usage)
        [sanitized_input]
      end
    end
  end
end
