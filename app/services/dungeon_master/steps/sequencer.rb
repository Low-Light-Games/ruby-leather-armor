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

        prompt_summary = "Sequencer: \"#{@log.truncate(sanitized_input)}\""
        system_prompt = PromptRenderer.render("sequencer")
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        parsed = timed_ai_call("sequencer", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                          max_tokens: @config.token_budget_for("sequencer"), step_name: "sequencer",
                          model: @config.model_for("sequencer"))
          [raw, @ai.parse_json(raw)]
        end

        actions = Array(parsed["actions"]).map(&:strip).reject(&:blank?)
        actions = [sanitized_input] if actions.empty?

        if actions.size > 1
          @log.dm_log!("Sequencer detected #{actions.size} sequential actions: #{actions.inspect}")
        end

        actions
      rescue TokenBudgetExceededError, AiError
        [sanitized_input]
      end
    end
  end
end
