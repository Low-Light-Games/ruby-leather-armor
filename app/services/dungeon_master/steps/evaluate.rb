# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 4: Evaluate.
    # Resolves dice roll results against ruling summaries and produces
    # structured mutations (HP changes, conditions, items consumed).
    module Evaluate
      private

      def run_evaluate(intent, merged, roll_results:, npc_results:)
        raw = nil
        prompt_summary = "Evaluate: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = {
          traversal: @adventure.traversal_context,
          combat: @adventure.combat_context,
          social: @adventure.social_context
        }

        char_block = @sheet ? CharacterBlock.full(@sheet) : "Unknown character"
        all_roll_results = [roll_results, npc_results].reject(&:blank?).join("\n\n")

        system_prompt = PromptRenderer.render("evaluate",
          character_block: char_block,
          ruling_summaries_text: merged[:ruling_summaries].join("\n\n"),
          roll_results: all_roll_results,
          consequences: merged[:consequences].present? ? merged[:consequences].to_json : nil,
          contexts_text: PromptHelpers.format_contexts(micro_contexts))

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
        raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                        max_tokens: @config.token_budget_for("evaluate"), step_name: "evaluate",
                        model: @config.model_for("evaluate"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("evaluate", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          outcome: parsed["outcome"] || "The action resolves.",
          mutations: parsed["mutations"] || {}
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("evaluate", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("evaluate", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end
    end
  end
end
