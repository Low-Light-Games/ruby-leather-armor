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
      return resolve_with_mechanics(intent, evaluations) if intent[:needs_mechanics]

      resolve_without_mechanics(intent)
    end

    def resolve_with_mechanics(intent, evaluations)
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

      merged = merge_mechanical_evaluations_and_prepare_rolls(evaluations)
      return { status: :awaiting_rolls, intent: intent, merged: merged } if merged[:player_rolls].any?

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

      return resolve_social_scene(intent) if intent[:expand_scene]

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

    def skip_world_sanity_for_privileged_player?
      @adventure.skip_world_sanity_check? && (@adventure.user.paid? || @adventure.user.admin)
    end

    # Post-roll completion: verdict → mutations → time_keeper
    def finish_resolution(intent, merged, roll_results, requested_rolls: nil, submitted_rolls: nil)
      # In active combat, world turn resolves routine NPC turns. Only immediate
      # reactions (see mechanical_evaluation/_combat) pass through here with the
      # player's rolls so AoO-style events resolve before the turn advances.
      effective_npc_actions = MechanicalEvaluationNpcActions.filter_for_combat_finish(
        merged[:npc_actions],
        combat_active: combat_active?
      )
      npc_results = resolve_npc_actions(effective_npc_actions)
      verdict_result = if combat_active?
                         run_combat_gm(intent, merged, roll_results: roll_results, npc_results: npc_results)
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
        return {
          status: :awaiting_initiative,
          intent: intent,
          creature_data: intent[:creature_data],
          mutations: verdict_result[:mutations]
        }
      end

      maybe_run_world_turn(
        status: :resolved, intent: intent,
        mutations: verdict_result[:mutations],
        time_result: time_result,
        action_outcome: verdict_result[:outcome].to_s.presence,
        queue_resolution_context: {
          player_rolls: Array(requested_rolls.presence || merged[:player_rolls]).map { |r| r.is_a?(Hash) ? r.deep_dup : r },
          submitted_rolls: Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r },
          roll_results: roll_results
        }
      )
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

      {
        status: :social_scene, intent: intent
      }
    end

    def store_pipeline_outcome!(text)
      if text.blank?
        @log&.play_log!("empty_pipeline_outcome", "Terminal wrote blank pipeline_outcome — narration context will be missing")
      end

      @loop&.batch_update!(new_data: { "pipeline_outcome" => text.to_s.truncate(2000) })
    end
  end
end
