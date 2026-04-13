# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Dedicated combat adjudicator after rolls when combat is active.
    # Replaces Mechanic for verdict + mutations; owns PF1e combat synthesis and battlefield patches.
    module CombatGm
      private

      def run_combat_gm(intent, merged, roll_results:, npc_results:)
        prompt_summary = "Combat GM: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        raise AiError, "Combat GM reached without a character sheet — cannot resolve combat" unless @sheet
        Battlefield::EnsureForActiveCombat.call(adventure: @adventure, sheet: @sheet)
        @adventure.reload

        char_block = CharacterBlock.full(@sheet)
        all_roll_results = [roll_results, npc_results].reject(&:blank?).join("\n\n")
        creature_stats = CharacterBlock.creature_stats_for(@adventure)
        battlefield_text = Battlefield::PromptSerializer.slice_for_adventure(@adventure)
        action_economy = (@adventure.combat_context || {})["action_economy"]
        combat_rules = Rules.guidance_for("combat")

        system_prompt = PromptRenderer.render("combat_gm",
          character_block: char_block,
          mechanical_summaries_text: merged[:mechanical_summaries].join("\n\n"),
          roll_results: all_roll_results,
          consequences: merged[:consequences].present? ? merged[:consequences].to_json : nil,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          creature_stats: creature_stats,
          battlefield_text: battlefield_text,
          action_economy_json: action_economy.present? ? action_economy.to_json : "(none)",
          combat_rules: combat_rules.presence || "(see core PF1e CRB combat chapter)")

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("combat_gm", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          max_tokens: @config.token_budget_for("combat_gm"), step_name: "combat_gm",
                          model: @config.model_for("combat_gm"))
          [raw, @ai.parse_json(raw)]
        end

        raise AiError, "Combat GM returned no outcome — model produced: #{parsed.inspect.truncate(200)}" unless parsed["outcome"].present?

        {
          outcome: parsed["outcome"],
          mutations: parsed["mutations"] || {}
        }
      end
    end
  end
end
