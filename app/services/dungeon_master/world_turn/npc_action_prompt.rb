# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    # Assembles Node evaluator payloads for the npc_action step (system/user prompts + meta).
    # Creature lines use {CharacterBlock.creature_npc_action_prompt} — same “block text for LLMs”
    # role as other CharacterBlock helpers, not ad-hoc string building in the step.
    module NpcActionPrompt
      module_function

      def meta_step(npc, idx)
        "npc_action_#{npc.creature_sheet_id}_#{idx}"
      end

      # @param last_outcome [String] truncated pipeline_outcome seed for the loop
      # @return [Hash] evaluator fan_out item (symbol keys for :meta)
      def evaluator_payload(npc:, combat_ctx:, slot:, config:, adventure:, last_outcome:)
        creature_sheet = adventure.creature_sheets.find_by(id: npc.creature_sheet_id)
        creature_block = if creature_sheet
                           CharacterBlock.creature_npc_action_prompt(creature_sheet)
                         else
                           npc.to_context_hash.to_json
                         end

        combat_summary = combat_ctx.except("participants").to_json
        participants_line = Array(combat_ctx["participants"]).map { |x| x["name"] }.join(", ")
        system_prompt, user_msg = PromptRenderer.render_with_user_message("npc_action",
          npc_name: npc.name,
          creature_block: creature_block,
          combat_summary: "#{combat_summary}\nParticipants: #{participants_line}",
          last_outcome: last_outcome.presence || "(none)")

        {
          system_prompt: system_prompt,
          user_message: user_msg || "Decide action.",
          model: config.model_for("npc_action"),
          max_tokens: config.token_budget_for("npc_action"),
          meta: { step: meta_step(npc, slot) }
        }
      end
    end
  end
end
