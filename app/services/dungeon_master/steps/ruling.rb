# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Ruling (post-rolls arbitration).
    # Resolves dice roll results against mechanical evaluation summaries and
    # produces structured mutations (HP changes, conditions, items consumed).
    #
    # This was previously the "Evaluate" step. Renamed to reflect its true role:
    # arbitering the outcome of an action after rolls are resolved.
    module Ruling
      private

      def run_ruling(intent, merged, roll_results:, npc_results:)
        raw = nil
        prompt_summary = "Ruling: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)

        raise AiError, "Ruling step reached without a character sheet — cannot resolve mechanics" unless @sheet
        char_block = CharacterBlock.full(@sheet)
        all_roll_results = [roll_results, npc_results].reject(&:blank?).join("\n\n")

        system_prompt = PromptRenderer.render("ruling",
          character_block: char_block,
          mechanical_summaries_text: merged[:mechanical_summaries].join("\n\n"),
          roll_results: all_roll_results,
          consequences: merged[:consequences].present? ? merged[:consequences].to_json : nil,
          contexts_text: PromptHelpers.format_contexts(micro_contexts))

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
        raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                        max_tokens: @config.token_budget_for("ruling"), step_name: "ruling",
                        model: @config.model_for("ruling"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("ruling", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        raise AiError, "Ruling step returned no outcome — model produced: #{raw.to_s.truncate(200)}" unless parsed["outcome"].present?

        {
          outcome: parsed["outcome"],
          mutations: parsed["mutations"] || {}
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("ruling", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("ruling", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end
    end
  end
end
