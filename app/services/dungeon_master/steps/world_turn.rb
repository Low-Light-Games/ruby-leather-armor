# frozen_string_literal: true

module DungeonMaster
  module Steps
    # World Turn: after the player's loop step resolves in active combat, runs
    # initiative-ordered NPC actions (fan-out + code dice), applies mutations,
    # emits +combat_state_advancement+ for ContextUpdate, and appends a short
    # summary to +pipeline_outcome+.
    #
    # Semantic note: during combat, +pipeline_outcome+ is intentionally a
    # **full-round narration seed** (player outcome plus NPC turn summary), not
    # player-only text — see AccumulatedAssembly / Narrate.
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
        return true if v.nil?
        return false if v == false
        return false if v.to_s.downcase == "disabled"

        true
      end

      # Appends to the current loop's pipeline_outcome (does not replace the
      # player's mechanical outcome written by +store_pipeline_outcome!+).
      def append_pipeline_outcome!(text)
        return if text.blank?

        cur = @loop&.get("pipeline_outcome").to_s
        chunk = text.to_s.strip
        merged = cur.present? ? "#{cur}\n\nWorld — #{chunk}" : chunk
        @loop&.batch_update!(new_data: { "pipeline_outcome" => merged.truncate(2000) })
      end

      def apply_player_flee_combat(result)
        advancement = build_combat_state_advancement("active" => false)
        result[:mutations] = merge_combat_advancement_into_mutations(result[:mutations], advancement)
        result[:combat_end_reason] = :player_fled
        result
      end

      def run_world_turn(result)
        broadcast_progress("The world reacts...")

        combat_ctx = (@adventure.combat_context || {}).deep_dup.deep_stringify_keys
        calc = Utilities::CombatTurnCalculator.call(combat_context: combat_ctx)
        npc_turns = calc[:npc_turns]

        lines = []
        npc_mutation_rows = []
        player_hp_delta = 0

        if npc_turns.any?
          evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")
          prompts = npc_turns.map.with_index { |npc, i| build_npc_action_evaluator_payload(npc, combat_ctx, i) }
          intention = result[:intent].is_a?(Hash) ? result[:intent][:intention].to_s : ""
          raw = call_evaluator!("#{evaluator_url}/fan_out", prompts, intention, phase: "npc_action")
          by_step = evaluator_fan_out_results_by_step(raw)

          npc_turns.each_with_index do |npc, i|
            step_key = npc_action_meta_step(npc, i)
            entry = evaluator_fan_out_result!(by_step, step_key, "npc_action")
            parsed = (entry["parsed_response"] || {}).deep_symbolize_keys
            res = resolve_npc_world_turn_action(npc, parsed, combat_ctx)
            lines.concat(res[:lines])
            npc_mutation_rows.concat(res[:npc_muts])
            player_hp_delta += res[:player_hp_delta].to_i
          end
        end

        if player_hp_delta != 0
          apply_player_mutations({ hp_change: player_hp_delta })
        end
        apply_npc_mutations(npc_mutation_rows) if npc_mutation_rows.any?

        @sheet&.reload
        if @sheet && @sheet.hp == 0 && !Array(@sheet.conditions).include?("disabled")
          apply_player_mutations({ conditions_add: ["disabled"] })
        end

        @on_sheet_update&.call
        @adventure.reload
        @sheet&.reload

        prose = lines.join("\n")
        append_pipeline_outcome!(prose) if prose.present?

        advancement = build_combat_state_advancement_after_world_turn(calc[:next_state], combat_ctx)
        end_info = Utilities::CombatEndResolver.check_combat_end(adventure: @adventure, sheet: @sheet)
        advancement = merge_combat_end_into_advancement(advancement, end_info)

        result[:mutations] = merge_combat_advancement_into_mutations(result[:mutations], advancement)
        result[:player_death] = true if end_info.dig(:interaction, :player_death)
        result[:player_incapacitated] = true if end_info.dig(:interaction, :player_incapacitated)
        result[:world_turn_summary] = prose.presence
        result
      end

      def merge_combat_end_into_advancement(advancement, end_info)
        adv = advancement.deep_stringify_keys
        adv["active"] = false if end_info[:combat][:combat_active] == false
        adv
      end

      def build_combat_state_advancement_after_world_turn(next_state_slice, original_ctx)
        ctx = original_ctx.deep_stringify_keys
        ns = (next_state_slice || {}).deep_stringify_keys
        participants = Array(ctx["participants"]).map { |p| rebuild_participant_from_canonical(p) }
        {
          "turn_order" => ctx["turn_order"],
          "terrain_notes" => ctx["terrain_notes"],
          "active_effects" => ctx["active_effects"],
          "participants" => participants,
          "round" => ns.key?("round") ? ns["round"] : ctx["round"],
          "current_turn" => ns.key?("current_turn") ? ns["current_turn"] : ctx["current_turn"],
          "active" => ns.key?("active") ? ns["active"] : (ctx["active"] != false)
        }
      end

      def build_combat_state_advancement(overrides = {})
        ctx = @adventure.combat_context.deep_stringify_keys
        participants = Array(ctx["participants"]).map { |p| rebuild_participant_from_canonical(p) }
        base = {
          "active" => ctx["active"],
          "round" => ctx["round"],
          "current_turn" => ctx["current_turn"],
          "turn_order" => ctx["turn_order"],
          "participants" => participants,
          "terrain_notes" => ctx["terrain_notes"],
          "active_effects" => ctx["active_effects"]
        }
        Utilities::HashMerge.deep_merge_presence(base, overrides.deep_stringify_keys)
      end

      def rebuild_participant_from_canonical(p)
        c = Utilities::Combatant.from_context_hash(p)
        if c.player?
          Utilities::Combatant.from_player_sheet(@sheet, initiative: c.initiative).to_context_hash
        elsif c.creature_sheet_id.present?
          sheet = @adventure.creature_sheets.find_by(id: c.creature_sheet_id)
          sheet ? Utilities::Combatant.from_creature_sheet(sheet, initiative: c.initiative).to_context_hash : c.to_context_hash
        else
          c.to_context_hash
        end
      end

      def merge_combat_advancement_into_mutations(existing, advancement)
        m = existing.is_a?(Hash) ? existing.deep_dup : {}
        m.deep_stringify_keys.merge("combat_state_advancement" => advancement.deep_stringify_keys)
      end

      def npc_action_meta_step(npc, idx)
        "npc_action_#{npc.creature_sheet_id}_#{idx}"
      end

      def build_npc_action_evaluator_payload(npc, combat_ctx, idx)
        sheet = @adventure.creature_sheets.find_by(id: npc.creature_sheet_id)
        creature_block = format_npc_creature_prompt_block(sheet, npc)
        combat_summary = combat_ctx.except("participants").to_json
        participants_line = Array(combat_ctx["participants"]).map { |x| x["name"] }.join(", ")
        last_outcome = @loop&.get("pipeline_outcome").to_s.truncate(800)
        system_prompt, user_msg = PromptRenderer.render_with_user_message("npc_action",
          npc_name: npc.name,
          creature_block: creature_block,
          combat_summary: "#{combat_summary}\nParticipants: #{participants_line}",
          last_outcome: last_outcome.presence || "(none)")

        {
          system_prompt: system_prompt,
          user_message: user_msg || "Decide action.",
          model: @config.model_for("npc_action"),
          max_tokens: @config.token_budget_for("npc_action"),
          meta: { step: npc_action_meta_step(npc, idx) }
        }
      end

      def format_npc_creature_prompt_block(sheet, npc)
        if sheet
          ds = sheet.derived_stats || {}
          [
            "#{sheet.name} (#{sheet.creature_type})",
            "HP #{sheet.hp}/#{sheet.max_hp}, AC #{ds['ac']}, BAB +#{ds['bab']}, Melee +#{ds['melee_attack'] || 0}, Ranged +#{ds['ranged_attack'] || 0}"
          ].join("\n")
        else
          npc.to_context_hash.to_json
        end
      end

      def resolve_npc_world_turn_action(npc, parsed, combat_ctx)
        action = parsed[:action].to_s.downcase
        lines = []
        npc_muts = []
        player_hp = 0

        case action
        when "flee"
          lines << "#{npc.name} disengages and flees."
          npc_muts << { creature_sheet_id: npc.creature_sheet_id, name: npc.name, conditions_add: ["fled"] }
        when "surrender"
          lines << "#{npc.name} surrenders."
          npc_muts << { creature_sheet_id: npc.creature_sheet_id, name: npc.name, conditions_add: ["surrendered"] }
        when "attack"
          target = parsed[:target].to_s.strip
          target = Utilities::CombatTurnCalculator::PLAYER_NAME if target.blank? || target.casecmp("player").zero?
          mod = parsed[:attack_modifier].to_i
          dice = parsed[:damage_dice].presence || "1d4"

          if target == Utilities::CombatTurnCalculator::PLAYER_NAME
            ac = @sheet.derived_stats.fetch("ac").to_i
            roll = rand(1..20)
            total = roll + mod
            hit = total >= ac
            if hit
              dmg = roll_damage_expression(dice)
              lines << "#{npc.name} attacks Player: #{roll}+#{mod}=#{total} vs AC #{ac} — HIT for #{dmg}."
              player_hp -= dmg
            else
              lines << "#{npc.name} attacks Player: #{roll}+#{mod}=#{total} vs AC #{ac} — miss."
            end
          else
            ac = ac_for_participant_name(target, combat_ctx)
            if ac.nil?
              lines << "#{npc.name} attacks #{target} — invalid target."
            else
              roll = rand(1..20)
              total = roll + mod
              hit = total >= ac
              if hit
                dmg = roll_damage_expression(dice)
                lines << "#{npc.name} attacks #{target}: hit for #{dmg}."
                tid = creature_sheet_id_for_participant_name(target, combat_ctx)
                npc_muts << { creature_sheet_id: tid, name: target, hp_change: -dmg } if tid.present?
              else
                lines << "#{npc.name} attacks #{target}: miss."
              end
            end
          end
        else
          lines << "#{npc.name} takes no decisive action."
        end

        { lines: lines, npc_muts: npc_muts, player_hp_delta: player_hp }
      end

      def creature_sheet_id_for_participant_name(name, combat_ctx)
        p = Array(combat_ctx["participants"]).find { |x| x["name"].to_s == name.to_s }
        sid = p && p["creature_sheet_id"]
        sid.present? ? sid.to_i : nil
      end

      def ac_for_participant_name(name, combat_ctx)
        return @sheet.derived_stats.fetch("ac").to_i if name.to_s.casecmp("player").zero?

        sid = creature_sheet_id_for_participant_name(name, combat_ctx)
        return nil unless sid
        c = @adventure.creature_sheets.find_by(id: sid)
        (c&.derived_stats || {})["ac"]&.to_i
      end

      def roll_damage_expression(expr)
        s = expr.to_s.strip.downcase.gsub(/\s+/, "")
        m = s.match(/\A(\d+)d(\d+)([+-]\d+)?\z/i)
        return rand(1..4) unless m

        count = m[1].to_i
        sides = m[2].to_i
        mod = m[3] ? m[3].to_i : 0
        count.times.sum { rand(sides) + 1 } + mod
      end
    end
  end
end
