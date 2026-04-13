# frozen_string_literal: true

module DungeonMaster
  module Steps
    # World Turn: after the player's loop step resolves in active combat, runs
    # initiative-ordered NPC actions (sequential evaluator calls + code dice), applies mutations,
    # emits +combat_state_advancement+ for ContextUpdate, and appends a short
    # summary to +pipeline_outcome+.
    #
    # Orchestration only — collaborators live in {DungeonMaster::WorldTurn} and
    # {DungeonMaster::Rolls::CombatDice} (+ {CharacterBlock} for NPC prompt lines).
    #
    # During combat, +pipeline_outcome+ is a full-round narration seed; see AccumulatedAssembly.
    module WorldTurn
      private

      def maybe_run_world_turn(result)
        return result unless combat_active?
        return result unless world_turn_enabled?

        @adventure.reload
        @sheet&.reload

        intent = result[:intent] || {}
        return apply_player_flee_combat(result) if intent[:combat_ending]

        run_world_turn(result)
      end

      def world_turn_enabled?
        v = @config.get("world_turn")
        v != false && v.to_s.downcase != "disabled"
      end

      def append_pipeline_outcome!(text)
        return if text.blank?

        cur = @loop&.get("pipeline_outcome").to_s
        chunk = text.to_s.strip
        merged = cur.present? ? "#{cur}\n\nWorld — #{chunk}" : chunk
        @loop&.batch_update!(new_data: { "pipeline_outcome" => merged.truncate(2000) })
      end

      def apply_player_flee_combat(result)
        advancement = DungeonMaster::WorldTurn::CombatAdvancement.build_full(adventure: @adventure, sheet: @sheet,
          overrides: { "active" => false })
        result[:mutations] = DungeonMaster::WorldTurn::CombatAdvancement.merge_into_mutations(result[:mutations], advancement)
        result
      end

      def run_world_turn(result)
        broadcast_progress("The world reacts...")

        base_ctx = (@adventure.combat_context || {}).deep_dup.deep_stringify_keys
        calc = Utilities::CombatTurnCalculator.call(combat_context: base_ctx)
        npc_turns = calc[:npc_turns]

        lines = []
        evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")
        intention = result[:intent].is_a?(Hash) ? result[:intent][:intention].to_s : ""
        early_stop = false
        prompt_slot = 0
        last_outcome = @loop&.get("pipeline_outcome").to_s.truncate(800)

        npc_turns.each do |npc|
          @adventure.reload
          @sheet&.reload

          working_ctx = DungeonMaster::WorldTurn::LiveContext.merge_live_participants(base_ctx, adventure: @adventure, sheet: @sheet)
          fighter_row = working_ctx["participants"].find { |p| p["creature_sheet_id"].to_i == npc.creature_sheet_id.to_i }
          next if fighter_row.blank?

          fighter = Utilities::Combatant.from_context_hash(fighter_row)
          next if fighter.eliminated_from_encounter? || !fighter.can_act?

          prompt = DungeonMaster::WorldTurn::NpcActionPrompt.evaluator_payload(
            npc: npc, combat_ctx: working_ctx, slot: prompt_slot, config: @config,
            adventure: @adventure, last_outcome: last_outcome)
          prompt_slot += 1
          step_key = prompt[:meta][:step]

          raw = call_evaluator!("#{evaluator_url}/fan_out", [prompt], intention, phase: "npc_action")
          by_step = evaluator_fan_out_results_by_step(raw)
          entry = evaluator_fan_out_result!(by_step, step_key, "npc_action")
          parsed = (entry["parsed_response"] || {}).deep_symbolize_keys

          res = DungeonMaster::WorldTurn::NpcActionResolver.resolve(
            npc: npc, parsed: parsed, combat_ctx: working_ctx,
            player_sheet: @sheet, adventure: @adventure)
          lines.concat(res[:lines])

          apply_world_turn_step_mutations!(res[:player_hp_delta], res[:npc_muts])

          @sheet&.reload
          if @sheet && @sheet.hp == 0 && !Array(@sheet.conditions).include?("disabled")
            apply_player_mutations({ conditions_add: ["disabled"] })
          end

          @on_sheet_update&.call

          end_info = Utilities::CombatEndResolver.check_combat_end(
            adventure: @adventure.reload, sheet: (@sheet&.reload))
          if !end_info[:combat][:combat_active] ||
              end_info.dig(:interaction, :player_death) ||
              end_info.dig(:interaction, :player_incapacitated)
            early_stop = true
            break
          end
        end

        @adventure.reload
        @sheet&.reload

        prose = lines.join("\n")
        append_pipeline_outcome!(prose) if prose.present?

        next_slice = if early_stop
                       {
                         "current_turn" => Utilities::CombatTurnCalculator::PLAYER_NAME,
                         "round" => base_ctx["round"].to_i
                       }
                     else
                       calc[:next_state]
                     end

        advancement = DungeonMaster::WorldTurn::CombatAdvancement.build_after_world_turn(
          next_slice, base_ctx, adventure: @adventure, sheet: @sheet)
        end_info = Utilities::CombatEndResolver.check_combat_end(adventure: @adventure, sheet: @sheet)
        advancement = DungeonMaster::WorldTurn::CombatAdvancement.merge_combat_end_into_advancement(advancement, end_info)

        result[:mutations] = DungeonMaster::WorldTurn::CombatAdvancement.merge_into_mutations(result[:mutations], advancement)
        result[:player_death] = true if end_info.dig(:interaction, :player_death)
        result[:player_incapacitated] = true if end_info.dig(:interaction, :player_incapacitated)
        result
      end

      def apply_world_turn_step_mutations!(player_hp_delta, npc_muts)
        if player_hp_delta.to_i != 0
          apply_player_mutations({ hp_change: player_hp_delta.to_i })
        end
        apply_npc_mutations(npc_muts) if npc_muts.any?
      end
    end
  end
end
