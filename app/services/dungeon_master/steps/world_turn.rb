# frozen_string_literal: true

module DungeonMaster
  module Steps
    # World Turn: after the player's loop step resolves in active combat, runs
    # initiative-ordered NPC actions (parallel AI from one shared snapshot; code resolves dice + mutations in order),
    # emits +combat_state_advancement+ for ContextUpdate, and appends a short
    # summary to +pipeline_outcome+.
    #
    # Orchestration only — collaborators live in {DungeonMaster::WorldTurn} and
    # {DungeonMaster::Rolls::CombatDice} (+ {CharacterBlock} for NPC prompt lines).
    #
    # During combat, +pipeline_outcome+ is a full-round narration seed; see AccumulatedAssembly.
    module WorldTurn
      PIPELINE_OUTCOME_TRUNCATE = 2000
      NPC_ACTION_LAST_OUTCOME_TRUNCATE = 800

      private

      def maybe_run_world_turn(result)
        return result unless combat_active?

        reload_world_turn_records!

        intent = result[:intent] || {}
        return apply_player_flee_combat(result) if intent[:combat_ending]

        run_world_turn(result)
      end

      def append_pipeline_outcome!(text)
        return if text.blank?

        cur = @loop&.get("pipeline_outcome").to_s
        chunk = text.to_s.strip
        merged = cur.present? ? "#{cur}\n\nWorld — #{chunk}" : chunk
        @loop&.batch_update!(new_data: { "pipeline_outcome" => merged.truncate(PIPELINE_OUTCOME_TRUNCATE) })
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
        calc     = Utilities::CombatTurnCalculator.call(combat_context: base_ctx)
        instant_death = @config.instant_death?

        # Short-circuit before NPC fan-out if the player is already dead.
        # Covers both instant_death (HP 0 = dead) and standard PF1e (HP <= -CON from CombatGM).
        if @sheet &&
            Utilities::CombatEndResolver.check_player_status(@sheet, instant_death: instant_death) == :dead
          return build_result_with_combat_advancement(result, calc, base_ctx, true)
        end

        # Apply per-round dying bleed-out before NPC actions. Skipped once stabilized.
        # Under instant_death, HP cannot go negative so :dying is never reached.
        # Short-circuits if the player dies this round.
        if @sheet &&
            Utilities::CombatEndResolver.check_player_status(@sheet, instant_death: instant_death) == :dying &&
            !Array(@sheet.conditions).include?("stabilized")
          bleed_result = apply_dying_bleed!(result)
          return bleed_result if bleed_result
        end

        # Under standard PF1e, HP 0 = disabled (not yet dying). Apply the condition
        # here, before NPC fan-out, so it is always set regardless of whether any
        # NPCs act this round. (Previously this only ran inside the per-NPC loop,
        # meaning the condition was silently skipped on rounds with no acting NPCs.)
        if @sheet && !instant_death && @sheet.hp == 0 && !Array(@sheet.conditions).include?("disabled")
          apply_player_mutations({ conditions_add: ["disabled"] })
        end

        working_ctx = DungeonMaster::WorldTurn::LiveContext.merge_live_participants(
          base_ctx, adventure: @adventure, sheet: @sheet)

        # Rows from live merge (same initiative order as calc); not raw CombatTurnCalculator objects.
        acting_npcs = filter_acting_npcs(calc[:npc_turns], working_ctx)

        lines, early_stop = resolve_npc_turns_in_order(acting_npcs, working_ctx, result, instant_death: instant_death)

        @on_sheet_update&.call
        reload_world_turn_records!

        append_pipeline_outcome!(lines.join("\n")) if lines.any?
        result[:world_turn_lines] = lines.dup if lines.any?

        build_result_with_combat_advancement(result, calc, base_ctx, early_stop)
      end

      def filter_acting_npcs(npc_turns, working_ctx)
        npc_turns.filter_map do |npc|
          row = working_ctx["participants"].find { |p| p["creature_sheet_id"].to_i == npc.creature_sheet_id.to_i }
          next if row.blank?

          fighter = Utilities::Combatant.from_context_hash(row)
          fighter if !fighter.eliminated_from_encounter? && fighter.can_act?
        end
      end

      # Fans out AI NPC action requests, then resolves them in initiative order against
      # live DB state. Returns [lines, early_stop].
      def resolve_npc_turns_in_order(acting_npcs, working_ctx, result, instant_death:)
        lines      = []
        early_stop = false
        return [lines, early_stop] unless acting_npcs.any?

        intention    = result[:intent].is_a?(Hash) ? result[:intent][:intention].to_s : ""
        last_outcome = @loop&.get("pipeline_outcome").to_s.truncate(NPC_ACTION_LAST_OUTCOME_TRUNCATE)
        step_keys, by_step = request_npc_actions(acting_npcs, working_ctx, intention, last_outcome)

        # AI decisions were made against working_ctx (frozen snapshot).
        # Mutations are applied in initiative order against live DB state so each hit
        # is HP-clamped before the next NPC acts.
        acting_npc_ids = acting_npcs.map(&:creature_sheet_id)
        live_sheets    = @adventure.creature_sheets.where(id: acting_npc_ids).index_by(&:id)

        acting_npcs.each_with_index do |npc, idx|
          if npc.creature_sheet_id.blank?
            @log.play_log!(
              "pipeline_error",
              "World turn participant missing creature_sheet_id: #{npc.name}",
              parsed_response: { npc: npc.name, combat_context: working_ctx }
            )
            raise AiError, "World turn participant missing creature_sheet_id for #{npc.name}"
          end

          # Liveness from the map; refreshed after each mutation cycle so a prior NPC's
          # action that incapacitates this one is visible here.
          live_sheet = live_sheets[npc.creature_sheet_id]
          if live_sheet.nil? || live_sheet.hp <= 0 ||
              (Array(live_sheet.conditions) & %w[dead fled surrendered]).any?
            next
          end

          reload_player_sheet!
          entry  = evaluator_fan_out_result!(by_step, step_keys[idx], "npc_action")
          parsed = (entry["parsed_response"] || {}).deep_symbolize_keys

          res = DungeonMaster::WorldTurn::NpcActionResolver.resolve(
            npc: npc, parsed: parsed, combat_ctx: working_ctx,
            player_sheet: @sheet, adventure: @adventure)
          lines.concat(res[:lines])

          @log.play_log!(
            "world_turn_resolution",
            "World turn: #{npc.name} — #{res[:lines].join(' | ').truncate(200)}",
            parsed_response: {
              npc: npc.name, action: parsed[:action],
              attack_modifier: parsed[:attack_modifier], damage_dice: parsed[:damage_dice],
              player_hp_delta: res[:player_hp_delta], npc_mutations: res[:npc_muts],
              lines: res[:lines]
            }
          )

          apply_world_turn_step_mutations!(res[:player_hp_delta].to_i, res[:npc_muts])
          Battlefield::ApplyPatches.call(adventure: @adventure, patches: res[:battlefield_patches], log: @log) if res[:battlefield_patches].present?

          reload_world_turn_records!
          live_sheets.merge!(@adventure.creature_sheets.where(id: acting_npc_ids).index_by(&:id))

          end_info = Utilities::CombatEndResolver.check_combat_end(adventure: @adventure, sheet: @sheet, instant_death: instant_death)
          if !end_info[:combat][:combat_active] ||
              end_info.dig(:interaction, :player_death) ||
              end_info.dig(:interaction, :player_incapacitated)
            early_stop = true
            break
          end
        end

        [lines, early_stop]
      end

      def build_result_with_combat_advancement(result, calc, base_ctx, early_stop)
        next_slice = if early_stop
                       { "current_turn" => Utilities::CombatTurnCalculator::PLAYER_NAME,
                         "round" => base_ctx["round"].to_i }
                     else
                       calc[:next_state]
                     end

        advancement = DungeonMaster::WorldTurn::CombatAdvancement.build_after_world_turn(
          next_slice, base_ctx, adventure: @adventure, sheet: @sheet)
        end_info    = Utilities::CombatEndResolver.check_combat_end(adventure: @adventure, sheet: @sheet, instant_death: @config.instant_death?)
        advancement = DungeonMaster::WorldTurn::CombatAdvancement.merge_combat_end_into_advancement(advancement, end_info)

        result[:mutations]           = DungeonMaster::WorldTurn::CombatAdvancement.merge_into_mutations(result[:mutations], advancement)
        result[:player_death]        = true if end_info.dig(:interaction, :player_death)
        result[:player_incapacitated] = true if end_info.dig(:interaction, :player_incapacitated)
        result
      end

      def apply_world_turn_step_mutations!(player_hp_delta, npc_muts)
        if player_hp_delta.to_i != 0
          apply_player_mutations({ hp_change: player_hp_delta.to_i })
        end
        apply_npc_mutations(npc_muts) if npc_muts.any?
      end

      # PF1e dying bleed-out: −1 HP per round + DC 10 CON stabilization roll.
      # Returns a completed result hash if the player dies this round; nil to continue.
      def apply_dying_bleed!(result)
        apply_player_mutations({ hp_change: -1 })
        @sheet&.reload

        if Utilities::CombatEndResolver.check_player_status(@sheet, instant_death: @config.instant_death?) == :dead
          lines = ["#{@sheet&.name || 'The player'} has bled out and died."]
          append_pipeline_outcome!(lines.join)

          advancement = DungeonMaster::WorldTurn::CombatAdvancement.build_full(
            adventure: @adventure, sheet: @sheet, overrides: { "active" => false })
          result[:mutations] = DungeonMaster::WorldTurn::CombatAdvancement.merge_into_mutations(result[:mutations], advancement)
          result[:player_death] = true
          return result
        end

        # DC 10 CON stabilization roll (d20 + CON modifier).
        con_mod = @sheet.derived_stats.dig("mods", "constitution").to_i
        roll = Rolls::CombatDice.roll_d20
        if roll + con_mod >= 10
          apply_player_mutations({ conditions_add: ["stabilized"] })
          append_pipeline_outcome!("#{@sheet&.name || 'The player'} stabilizes (CON check: #{roll}+#{con_mod}).")
        else
          append_pipeline_outcome!("#{@sheet&.name || 'The player'} continues to bleed (CON check: #{roll}+#{con_mod}, HP now #{@sheet&.hp}).")
        end

        nil
      end

      # Builds one evaluator payload per acting NPC, fans them out in a single HTTP
      # request, and returns [step_keys, by_step] for initiative-order resolution.
      # step_keys is the authoritative ordered list; by_step is keyed by meta["step"].
      def request_npc_actions(acting_npcs, working_ctx, intention, last_outcome)
        payloads = acting_npcs.each_with_index.map do |npc, slot|
          DungeonMaster::WorldTurn::NpcActionPrompt.evaluator_payload(
            npc: npc, combat_ctx: working_ctx, slot: slot, config: @config,
            adventure: @adventure, last_outcome: last_outcome)
        end
        step_keys = payloads.map { |p| p.delete(:step_key) }
        [step_keys, evaluator_fan_out!(payloads, intention, phase: "npc_action")]
      end

      def reload_world_turn_records!
        @adventure.reload
        @sheet&.reload
      end

      def reload_player_sheet!
        @sheet&.reload
      end
    end
  end
end
