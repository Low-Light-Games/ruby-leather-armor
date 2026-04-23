# frozen_string_literal: true

module DungeonMaster
  # Resolves a single **AdventureLoop** step in the current pipeline run: parallel evaluation,
  # sanity gate, mechanical path (rolls / mechanic / verdict), time keeper, encounter dispatch,
  # social scene, and `pipeline_outcome` persistence.
  #
  # Mixed into `Pipeline`. `ActionQueueRunner` calls `#resolve` once per queued player line;
  # `run_rolls` resumes via `#finish_resolution`.
  #
  # Returns a standardized result hash with :status indicating the outcome:
  #   :resolved             — loop step fully resolved, mutations available
  #   :awaiting_rolls       — rolls needed, intent and merged available for resumption
  #   :awaiting_initiative  — combat starting, waiting for player initiative roll
  #   :encounter            — Harbinger triggered an encounter mid-step
  #   :social_scene         — social scene expanded, pipeline_outcome written to loop
  #   :rejected             — SanityChecker rejected the intent
  module AdventureLoopResolution
    private

    # Full resolution: evaluation → sanity gate → [verdict + mutations + time_keeper]
    # Always uses Steps::ParallelEvaluation (Node microservice: beacon + mech_eval + roll_qualifier).
    def resolve(intention)
      intent, evaluations = run_parallel_evaluation(intention)
      return resolve_with_mechanics(intent, evaluations) if intent[:affected_contexts].any?

      resolve_without_mechanics(intent)
    end

    def resolve_with_mechanics(intent, evaluations)
      return resolve_social_scene_after_world_gate(intent) if social_scene_only?(intent)

      capability = if skip_world_sanity_for_privileged_player?
                     @loop&.log_step("sanity_checker", "World: skipped (player opt-out)")
                     run_capability_check(intent)
                   else
                     world, cap = run_sanity_gate_fan_out(intent)
                     return world_check_rejection(intent, world) unless world[:consistent]

                     @loop&.log_step("sanity_checker", "World: consistent")
                     cap
                   end

      return capability_check_rejection(intent, capability) unless capability[:allowed]

      return resolve_social_scene(intent) if intent[:expand_scene]

      merged = merge_mechanical_evaluations_and_prepare_rolls(evaluations)
      return PipelineFlowResults.awaiting_rolls(intent: intent, merged: merged).to_h if merged[:player_rolls].any?

      finish_resolution(intent, merged, Rolls::PlayerRolls.auto_success_roll_message(merged))
    end

    def resolve_without_mechanics(intent)
      if skip_world_sanity_for_privileged_player?
        @loop&.log_step("sanity_checker", "World: skipped (player opt-out, no mechanics)")
      else
        world = run_world_consistency_check(intent)
        return world_check_rejection(intent, world) unless world[:consistent]

        @loop&.log_step("sanity_checker", "World: consistent (no mechanics)")
      end
      time_result = run_time_keeper(intent, nil)
      return dispatch_encounter_warmaster(intent, time_result, mutations: nil) if time_result[:encounter]

      momentum_result = run_momentum(intent)
      maybe_run_world_turn(
        status: :resolved, intent: intent,
        mutations: momentum_result[:mutations].presence,
        time_result: time_result,
        action_outcome: momentum_result[:outcome].to_s.presence
      )
    end

    def social_scene_only?(intent)
      intent[:expand_scene] && Array(intent[:affected_contexts]).uniq == ["social"]
    end

    def resolve_social_scene_after_world_gate(intent)
      if skip_world_sanity_for_privileged_player?
        @loop&.log_step("sanity_checker", "World: skipped (player opt-out, social scene)")
      else
        world = run_world_consistency_check(intent)
        return world_check_rejection(intent, world) unless world[:consistent]

        @loop&.log_step("sanity_checker", "World: consistent (social scene)")
      end

      resolve_social_scene(intent)
    end

    def skip_world_sanity_for_privileged_player?
      # TODO: remove this once the world sanity, that piece of garbage, is actually working properly instead of killing every fucking things a player tries to do
      true # @adventure.skip_world_sanity_check? && (@adventure.user.paid? || @adventure.user.admin)
    end

    # Post-roll completion: verdict → mutations → time_keeper
    def finish_resolution(intent, merged, roll_results, requested_rolls: nil, submitted_rolls: nil)
      current_roll_requests = Array(requested_rolls.presence || merged[:player_rolls]).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r }
      if (damage_pause = maybe_pause_for_damage_roll(intent, merged, current_roll_requests, roll_results, submitted_rolls))
        return damage_pause
      end

      current_roll_requests, merged = ensure_damage_metadata_for_active_hit!(intent, merged, current_roll_requests, submitted_rolls)
      if (damage_pause = maybe_pause_for_damage_roll(intent, merged, current_roll_requests, roll_results, submitted_rolls))
        return damage_pause
      end

      roll_results, submitted_rolls = merge_roll_chain_results(merged, roll_results, submitted_rolls)
      verdict_roll_requests = merge_roll_chain_requests(merged, current_roll_requests)

      # In active combat, world turn resolves routine NPC turns. Only immediate
      # reactions (see combat_mechanic prompt; attack_of_opportunity npc_actions) pass through here with the
      # player's rolls so AoO-style events resolve before the turn advances.
      effective_npc_actions = MechanicalEvaluationNpcActions.filter_for_combat_finish(
        merged[:npc_actions],
        combat_active: combat_active?
      )
      npc_results = resolve_npc_actions(effective_npc_actions)
      verdict_result = if combat_active?
                         run_combat_gm(intent, merged,
                           roll_results: roll_results,
                           npc_results: npc_results,
                           roll_requests: verdict_roll_requests,
                           submitted_rolls: submitted_rolls)
                       else
                         run_mechanic(intent, merged, roll_results: roll_results, npc_results: npc_results)
                       end
      verdict_step = combat_active? ? "combat_gm" : "mechanic"
      @loop&.batch_update!(
        new_data: { "verdict_outcome" => verdict_result[:outcome].to_s.truncate(500) },
        timeline_entry: { "step" => verdict_step, "summary" => verdict_result[:outcome].to_s.truncate(120), "at" => Time.current.iso8601 })
      apply_mutations(verdict_result[:mutations])

      time_result = run_time_keeper(intent, verdict_result)

      if time_result[:encounter]
        return dispatch_encounter_warmaster(intent, time_result, mutations: verdict_result[:mutations])
      end

      store_pipeline_outcome!(verdict_result[:outcome])

      if prepared_hostile_combat_continues?(intent)
        return PipelineFlowResults.awaiting_initiative(
          intent: intent,
          creature_data: intent[:creature_data],
          mutations: verdict_result[:mutations],
          opener_outcome: verdict_result[:outcome].to_s.presence
        ).to_h
      end

      maybe_run_world_turn(
        status: :resolved, intent: intent,
        mutations: verdict_result[:mutations],
        time_result: time_result,
        action_outcome: verdict_result[:outcome].to_s.presence,
        queue_resolution_context: {
          player_rolls: current_roll_requests.map { |r| r.is_a?(Hash) ? r.deep_dup : r },
          submitted_rolls: Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r },
          roll_results: roll_results
        }
      )
    end

    def maybe_pause_for_damage_roll(intent, merged, current_roll_requests, roll_results, submitted_rolls)
      return nil if merged[:roll_chain].is_a?(Hash)

      hits = attack_rolls_requiring_damage(current_roll_requests, submitted_rolls)
      return nil if hits.empty?

      PipelineFlowResults.awaiting_rolls(
        intent: intent,
        merged: merged.merge(
          player_rolls: hits.map { |hit| build_damage_roll_request(hit) },
          roll_chain: {
            phase: "damage",
            prior_roll_results: roll_results,
            prior_submitted_rolls: Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r },
            prior_roll_requests: Array(current_roll_requests).map { |r| r.is_a?(Hash) ? r.deep_dup : r }
          }
        )
      ).to_h
    end

    def attack_rolls_requiring_damage(current_roll_requests, submitted_rolls)
      attack_rolls = current_roll_requests.filter_map do |roll|
        next unless roll.is_a?(Hash)

        next unless roll[:type].to_s == "attack_roll"

        next if roll[:damage].blank?

        roll.deep_symbolize_keys
      end
      return [] if attack_rolls.empty?

      submitted_by_id, submitted_by_label = submitted_roll_indexes(submitted_rolls)

      attack_rolls.filter do |roll|
        total = submitted_roll_total_for(roll, submitted_by_id, submitted_by_label)
        total && total >= roll[:dc].to_i
      end
    end

    def build_damage_roll_request(attack_roll)
      attack_roll = attack_roll.deep_symbolize_keys
      {
        request_id: derived_damage_request_id(attack_roll),
        source_request_id: attack_roll[:request_id],
        type: "damage_roll",
        description: damage_roll_description_for(attack_roll),
        source_type: attack_roll[:source_type],
        source_id: attack_roll[:source_id],
        damage: attack_roll[:damage],
        damage_type: attack_roll[:damage_type],
        target: attack_roll[:target],
        domain: attack_roll[:domain]
      }.compact
    end

    def damage_roll_description_for(attack_roll)
      source = attack_roll[:description].presence || attack_roll[:spell].presence || "attack"
      "Damage roll for #{source}"
    end

    def merge_roll_chain_results(merged, roll_results, submitted_rolls)
      chain = merged[:roll_chain]
      return [roll_results, submitted_rolls] unless chain.is_a?(Hash)

      combined_results = [chain[:prior_roll_results], roll_results].reject(&:blank?).join("\n")
      combined_submitted_rolls = Array(chain[:prior_submitted_rolls]).map { |r| r.is_a?(Hash) ? r.deep_dup : r } +
                                 Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r }

      [combined_results, combined_submitted_rolls]
    end

    def merge_roll_chain_requests(merged, current_roll_requests)
      chain = merged[:roll_chain]
      return Array(current_roll_requests).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r } unless chain.is_a?(Hash)

      Array(chain[:prior_roll_requests]).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r } +
        Array(current_roll_requests).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r }
    end

    def normalize_roll_label(label)
      label.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
    end

    def submitted_roll_indexes(submitted_rolls)
      Array(submitted_rolls).each_with_object([{}, {}]) do |roll, (by_id, by_label)|
        next unless roll.is_a?(Hash)

        normalized = roll.deep_symbolize_keys
        by_id[normalized[:request_id].to_s] = normalized[:roll_value].to_i if normalized[:request_id].present?
        by_label[normalize_roll_label(normalized[:roll_description])] = normalized[:roll_value].to_i
      end
    end

    def submitted_roll_total_for(roll, submitted_by_id, submitted_by_label)
      request_id = roll[:request_id].to_s
      return submitted_by_id[request_id] if request_id.present? && submitted_by_id.key?(request_id)

      submitted_by_label[normalize_roll_label(roll[:description])]
    end

    def derived_damage_request_id(attack_roll)
      base = attack_roll[:request_id].presence
      unless base.present?
        base = SecureRandom.uuid
        @log.play_log!(
          "warn",
          "Synthesized damage roll request_id without source request_id",
          parsed_response: { attack_roll: attack_roll }
        )
      end
      "#{base}:damage"
    end

    def ensure_damage_metadata_for_active_hit!(intent, merged, current_roll_requests, submitted_rolls)
      return [current_roll_requests, merged] unless combat_active?

      missing = attack_rolls_missing_damage_metadata(current_roll_requests, submitted_rolls)
      return [current_roll_requests, merged] if missing.empty?

      retried_rolls = retry_attack_damage_metadata(intent, current_roll_requests)
      repaired_requests = merge_retried_roll_requests(current_roll_requests, retried_rolls)
      still_missing = attack_rolls_missing_damage_metadata(repaired_requests, submitted_rolls)
      return [repaired_requests, merged.merge(player_rolls: repaired_requests)] if still_missing.empty?

      @log.play_log!(
        "pipeline_error",
        "Active-combat attack hit missing damage metadata after retry",
        parsed_response: {
          intention: intent[:intention],
          missing_requests: still_missing
        }
      )
      raise AiError, "Active-combat attack hit missing damage metadata after retry"
    end

    def attack_rolls_missing_damage_metadata(current_roll_requests, submitted_rolls)
      attack_rolls = Array(current_roll_requests).filter_map do |roll|
        next unless roll.is_a?(Hash)

        sym = roll.deep_symbolize_keys
        next unless sym[:type].to_s == "attack_roll"

        next unless attack_roll_missing_damage_metadata?(sym)

        sym
      end
      return [] if attack_rolls.empty?

      submitted_by_id, submitted_by_label = submitted_roll_indexes(submitted_rolls)
      attack_rolls.filter do |roll|
        total = submitted_roll_total_for(roll, submitted_by_id, submitted_by_label)
        total && total >= roll[:dc].to_i
      end
    end

    def retry_attack_damage_metadata(intent, current_roll_requests)
      retry_intention = <<~MSG
        #{intent[:intention]}

        Retry reason: an active-combat attack roll hit and still needs structural damage metadata.
        Re-emit the combat attack_rolls with `attack_option_id`, `target`, and `description`.
        Existing attack roll requests:
        #{Array(current_roll_requests).to_json}
      MSG
      prompts = build_mech_eval_prompts(["combat"], retry_intention, intent)
      results = evaluator_sequential!(prompts, retry_intention, phase: "mech_eval_retry")
      parse_mech_eval_results(results, ["combat"]).flat_map { |entry| entry[:player_rolls] }
    end

    def merge_retried_roll_requests(current_roll_requests, retried_rolls)
      retried_by_id, retried_by_label = Array(retried_rolls).each_with_object([{}, {}]) do |roll, (by_id, by_label)|
        next unless roll.is_a?(Hash)

        normalized = roll.deep_symbolize_keys
        by_id[normalized[:request_id].to_s] = normalized if normalized[:request_id].present?
        by_label[normalize_roll_label(normalized[:description])] = normalized
      end

      Array(current_roll_requests).map do |roll|
        next roll unless roll.is_a?(Hash)

        sym = roll.deep_symbolize_keys
        retried = if sym[:request_id].present?
                    retried_by_id[sym[:request_id].to_s]
                  end
        retried ||= retried_by_label[normalize_roll_label(sym[:description])]
        next sym unless retried

        sym.merge(
          attack_mode: retried[:attack_mode].presence || sym[:attack_mode],
          defense_kind: retried[:defense_kind].presence || sym[:defense_kind],
          source_type: retried[:source_type].presence || sym[:source_type],
          source_id: retried[:source_id].presence || sym[:source_id],
          damage: retried[:damage].presence || sym[:damage],
          damage_type: retried[:damage_type].presence || sym[:damage_type],
          target: retried[:target].presence || sym[:target]
        )
      end
    end

    def attack_roll_missing_damage_metadata?(roll)
      sym = roll.deep_symbolize_keys
      return true if sym[:attack_mode].blank?

      return true if sym[:defense_kind].blank?

      return true if sym[:damage].blank?

      return true if sym[:source_type].blank?

      return true if sym[:source_type].to_s != "unarmed" && sym[:source_id].blank?

      false
    end

    def prepared_hostile_combat_continues?(intent)
      return false if combat_active?

      prepared = Array(intent[:creature_data])
      return false if prepared.empty?

      # v1 assumption: the prepared creature_data set is the authoritative hostile roster
      # for deciding whether the opener should hand off into initiative.
      creature_ids = prepared.map { |entry| (entry[:creature_sheet_id] || entry["creature_sheet_id"]).to_i }.reject(&:zero?)
      return false if creature_ids.empty?

      @adventure.creature_sheets.where(id: creature_ids).any? do |sheet|
        sheet.hp.to_i > 0 && (Array(sheet.conditions) & %w[dead fled surrendered]).empty?
      end
    end

    # Harbinger Path A: delegate loop + warmaster glue, then persist narration seed here.
    def dispatch_encounter_warmaster(intent, time_result, mutations:)
      result = EncounterWarmasterBridge.call(
        loop: @loop, adventure: @adventure, sheet: @sheet, log: @log, config: @config, ai: @ai,
        intent: intent, time_result: time_result, mutations: mutations)
      store_pipeline_outcome!(result.pipeline_outcome)
      result.payload
    end

    # Social scene expansion: creates an immersive NPC interaction scene that
    # pauses the pipeline for player input. Analogous to encounter expansion
    # but for significant social interactions (transactions, negotiations, etc.).
    # TimeKeeper is skipped — no time passes until the interaction resolves.
    def resolve_social_scene(intent)
      prompt_summary = "SocialExpansion: \"#{@log.truncate(intent[:intention])}\""

      social_beacon = intent.dig(:domain_results, "social") || {}
      npc_names = begin
        @adventure.story.story_npcs.pluck(:name)
      rescue => e
        pipeline_error!("social_expansion_npcs", e)
      end

      system_prompt = PromptRenderer.render("social_expansion",
        loop: @loop,
        location: @adventure.current_location&.name || "the area",
        location_description: @adventure.current_location&.description,
        traversal_context: @adventure.traversal_context,
        social_context: @adventure.social_context,
        character_block: CharacterBlock.social(@sheet),
        npc_names: npc_names,
        domain_interpretation: social_beacon[:domain_interpretation] || intent[:intention])

      request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

      parsed = timed_ai_call("social_expansion", prompt_summary, request_body) do
        raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                        max_tokens: @config.token_budget_for("social_expansion"),
                        step_name: "social_expansion",
                        model: @config.model_for("social_expansion"))
        [raw, @ai.parse_json(raw)]
      end

      scene = parsed["scene"] || parsed["narrative"] || intent[:intention]
      npc_name = parsed["npc_name"]
      npc_attitude = parsed["npc_attitude"]
      new_elements = Array(parsed["new_elements"]).select(&:present?)

      if @loop
        loop_data = {
          "social_scene"    => scene.to_s.truncate(1000),
          "verdict_outcome" => scene.to_s.truncate(500)
        }
        loop_data["social_npc_name"] = npc_name if npc_name.present?
        loop_data["social_npc_attitude"] = npc_attitude if npc_attitude.present?
        loop_data["social_new_elements"] = new_elements if new_elements.any?
        @loop.batch_update!(
          new_data: loop_data,
          timeline_entry: { "step" => "social_expansion", "summary" => "Scene: #{npc_name || 'NPC'} (#{npc_attitude || 'unknown'})", "at" => Time.current.iso8601 })
      end

      store_pipeline_outcome!(scene)

      PipelineFlowResults.social_scene(intent: intent).to_h
    end

    def store_pipeline_outcome!(text)
      if text.blank?
        @log&.play_log!("empty_pipeline_outcome", "Terminal wrote blank pipeline_outcome — narration context will be missing")
      end

      @loop&.batch_update!(new_data: { "pipeline_outcome" => text.to_s.truncate(2000) })
    end
  end
end
