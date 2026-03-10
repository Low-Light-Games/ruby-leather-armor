# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Verdict (post-rolls arbitration).
    # Resolves dice roll results against mechanical evaluation summaries and
    # produces structured mutations (HP changes, conditions, items consumed).
    module Verdict
      private

      def run_verdict(intent, merged, roll_results:, npc_results:)
        prompt_summary = "Verdict: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)

        raise AiError, "Verdict step reached without a character sheet — cannot resolve mechanics" unless @sheet
        char_block = CharacterBlock.full(@sheet)
        all_roll_results = [roll_results, npc_results].reject(&:blank?).join("\n\n")

        system_prompt = PromptRenderer.render("verdict",
          character_block: char_block,
          mechanical_summaries_text: merged[:mechanical_summaries].join("\n\n"),
          roll_results: all_roll_results,
          consequences: merged[:consequences].present? ? merged[:consequences].to_json : nil,
          contexts_text: PromptHelpers.format_contexts(micro_contexts))

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("verdict", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          max_tokens: @config.token_budget_for("verdict"), step_name: "verdict",
                          model: @config.model_for("verdict"))
          [raw, @ai.parse_json(raw)]
        end

        raise AiError, "Verdict step returned no outcome — model produced: #{parsed.inspect.truncate(200)}" unless parsed["outcome"].present?

        {
          outcome: parsed["outcome"],
          mutations: parsed["mutations"] || {}
        }
      end
    end
  end
end
