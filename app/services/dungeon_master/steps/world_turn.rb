# frozen_string_literal: true

module DungeonMaster
  module Steps
    # World Turn: after the player's loop step resolves in active combat, applies
    # the NPC initiative-band actions emitted by the Combat GM (one AI call covers
    # the whole round). Code resolves dice + mutations in initiative order, emits
    # +combat_state_advancement+ for ContextUpdate, and appends a short summary
    # to +pipeline_outcome+.
    #
    # Orchestration only — collaborators live in {DungeonMaster::WorldTurn} and
    # {DungeonMaster::Rolls::CombatDice}.
    #
    # During combat, +pipeline_outcome+ is a full-round narration seed; see AccumulatedAssembly.
    module WorldTurn
      PIPELINE_OUTCOME_TRUNCATE = 2000

      private

      def instant_death_enabled?
        @config&.instant_death? == true
      end

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
        calc     = Utilities::CombatTurnCalculator.call(
          combat_context: base_ctx,
          player_acted_this_round: result[:precombat_opener] != true
        )
        instant_death = instant_death_enabled?

        # Short-circuit before NPC fan-out if the player is already dead.
        # Covers both instant_death (HP 0 = dead) and standard PF1e (HP <= -CON from CombatGM).
        if player_dead_before_npc_turns?(instant_death)
          return build_result_with_combat_advancement(result, calc, base_ctx, true)
        end

        # Apply per-round dying bleed-out before NPC actions. Skipped once stabilized.
        # Under instant_death, HP cannot go negative so :dying is never reached.
        # Short-circuits if the player dies this round.
        if should_apply_dying_bleed?(instant_death)
          bleed_result = apply_dying_bleed!(result)
          return bleed_result if bleed_result
        end

        # Under standard PF1e, HP 0 = disabled (not yet dying). Apply the condition
        # here, before NPC fan-out, so it is always set regardless of whether any
        # NPCs act this round. (Previously this only ran inside the per-NPC loop,
        # meaning the condition was silently skipped on rounds with no acting NPCs.)
        if should_apply_disabled_condition?(instant_death)
          apply_player_mutations({ conditions_add: ["disabled"] })
        end

        working_ctx = DungeonMaster::WorldTurn::LiveContext.merge_live_participants(
          base_ctx, adventure: @adventure, sheet: @sheet)

        # Rows from live merge (same initiative order as calc); not raw CombatTurnCalculator objects.
        acting_npcs = filter_acting_npcs(calc[:npc_turns], working_ctx)

        npc_action_plans = Array(result[:npc_actions])
        lines, early_stop = resolve_npc_turns_in_order(acting_npcs, working_ctx, npc_action_plans, instant_death: instant_death)

        @on_sheet_update&.call
        reload_world_turn_records!

        append_pipeline_outcome!(lines.join("\n")) if lines.any?
        result[:world_turn_lines] = lines.dup if lines.any?

        build_result_with_combat_advancement(result, calc, base_ctx, early_stop)
      end

      def filter_acting_npcs(npc_turns, working_ctx)
        npc_turns.filter_map do |npc|
          if npc.creature_sheet_id.blank?
            @log.play_log!(
              "pipeline_error",
              "World turn participant missing creature_sheet_id before participant lookup: #{npc.name}",
              parsed_response: { npc: npc.name, combat_context: working_ctx }
            )
            raise AiError, "World turn participant missing creature_sheet_id for #{npc.name}"
          end

          row = working_ctx["participants"].find { |p| p["creature_sheet_id"].to_i == npc.creature_sheet_id.to_i }
          next if row.blank?

          fighter = Utilities::Combatant.from_context_hash(row)
          fighter if !fighter.eliminated_from_encounter? && fighter.can_act?
        end
      end

      # Resolves Combat-GM-emitted NPC action plans in initiative order against
      # live DB state. Returns [lines, early_stop].
      def resolve_npc_turns_in_order(acting_npcs, working_ctx, npc_action_plans, instant_death:)
        lines      = []
        early_stop = false
        return [lines, early_stop] unless acting_npcs.any?

        plans_by_id = index_plans_by_creature_sheet_id(npc_action_plans)

        # Plans are applied in initiative order against live DB state so each hit
        # is HP-clamped before the next NPC acts.
        acting_npc_ids = acting_npcs.map(&:creature_sheet_id)
        live_sheets    = @adventure.creature_sheets.where(id: acting_npc_ids).index_by(&:id)

        acting_npcs.each do |npc|
          # Liveness from the map; refreshed after each mutation cycle so a prior NPC's
          # action that incapacitates this one is visible here.
          live_sheet = live_sheets[npc.creature_sheet_id]
          next if npc_sheet_unavailable_or_eliminated?(live_sheet)

          plan = plans_by_id[npc.creature_sheet_id.to_i]
          unless plan
            @log.play_log!(
              "world_turn_missing_plan",
              "World turn: no plan emitted for #{npc.name} (creature_sheet_id=#{npc.creature_sheet_id}); skipping.",
              parsed_response: { npc: npc.name, creature_sheet_id: npc.creature_sheet_id }
            )
            next
          end

          reload_player_sheet!

          npc_action_result = DungeonMaster::WorldTurn::NpcActionResolver.resolve(
            npc: npc, parsed: plan, combat_ctx: working_ctx,
            player_sheet: @sheet, adventure: @adventure)
          lines.concat(npc_action_result[:lines])
          npc_action_resolution_log_payload = DungeonMaster::WorldTurn::NpcActionResolutionLogPayload.new(
            npc_name: npc.name,
            action: plan[:action],
            attack_modifier: plan[:attack_modifier],
            damage_dice: plan[:damage_dice],
            player_hp_delta: npc_action_result[:player_hp_delta],
            npc_mutations: npc_action_result[:npc_muts],
            lines: npc_action_result[:lines]
          )

          @log.play_log!(
            "world_turn_resolution",
            "World turn: #{npc.name} — #{npc_action_result[:lines].join(' | ').truncate(200)}",
            parsed_response: npc_action_resolution_log_payload.to_h
          )

          apply_world_turn_step_mutations!(npc_action_result[:player_hp_delta].to_i, npc_action_result[:npc_muts])
          Battlefield::ApplyPatches.call(
            adventure: @adventure,
            patches: npc_action_result[:battlefield_patches],
            log: @log
          ) if npc_action_result[:battlefield_patches].present?

          reload_world_turn_records!
          live_sheets.merge!(@adventure.creature_sheets.where(id: acting_npc_ids).index_by(&:id))

          end_info = Utilities::CombatEndResolver.check_combat_end(adventure: @adventure, sheet: @sheet, instant_death: instant_death)
          if should_stop_world_turn_early?(end_info)
            early_stop = true
            break
          end
        end

        [lines, early_stop]
      end

      # Combat GM emits one entry per acting NPC, keyed by creature_sheet_id.
      # Symbolize so keys match the NpcActionResolver contract.
      def index_plans_by_creature_sheet_id(plans)
        Array(plans).each_with_object({}) do |raw, idx|
          next unless raw.is_a?(Hash)

          plan = raw.deep_symbolize_keys
          id   = plan[:creature_sheet_id].to_i
          next if id.zero?

          idx[id] = plan
        end
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
        end_info    = Utilities::CombatEndResolver.check_combat_end(adventure: @adventure, sheet: @sheet, instant_death: instant_death_enabled?)
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

        if Utilities::CombatEndResolver.check_player_status(@sheet, instant_death: instant_death_enabled?) == :dead
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

      def reload_world_turn_records!
        @adventure.reload
        @sheet&.reload
      end

      def reload_player_sheet!
        @sheet&.reload
      end

      def player_dead_before_npc_turns?(instant_death)
        @sheet && Utilities::CombatEndResolver.check_player_status(@sheet, instant_death: instant_death) == :dead
      end

      def should_apply_dying_bleed?(instant_death)
        return false unless @sheet

        Utilities::CombatEndResolver.check_player_status(@sheet, instant_death: instant_death) == :dying &&
          !Array(@sheet.conditions).include?("stabilized")
      end

      def should_apply_disabled_condition?(instant_death)
        @sheet && !instant_death && @sheet.hp == 0 && !Array(@sheet.conditions).include?("disabled")
      end

      def npc_sheet_unavailable_or_eliminated?(live_sheet)
        live_sheet.nil? || live_sheet.hp <= 0 || (Array(live_sheet.conditions) & %w[dead fled surrendered]).any?
      end

      def should_stop_world_turn_early?(end_info)
        !end_info[:combat][:combat_active] ||
          end_info.dig(:interaction, :player_death) ||
          end_info.dig(:interaction, :player_incapacitated)
      end
    end
  end
end
