# frozen_string_literal: true

module DungeonMaster
  # Inner pipeline: resolves a single player action from dispatch through time_keeper.
  #
  # Extracted from Pipeline's run_action_flow / run_resolution_flow so the
  # outer orchestrator (orchestrate_actions) can loop over queued actions
  # without duplicating resolution logic.
  #
  # Returns a standardized result hash with :status indicating the outcome:
  #   :resolved             — action fully resolved, mutations available
  #   :awaiting_rolls       — rolls needed, intent and merged available for resumption
  #   :awaiting_initiative  — combat starting, waiting for player initiative roll
  #   :encounter            — Harbinger triggered an encounter mid-action
  #   :social_scene         — social scene expanded, pipeline_outcome written to loop
  #   :rejected             — SanityChecker rejected the action
  module CoreResolver
    private

    # Full resolution: beacon → full gate (mech eval + world check + cap check) → [verdict + mutations + time_keeper]
    def resolve(intention)
      if @config.get("evaluation_mode") == "unified"
        return resolve_unified(intention)
      end

      intent = run_beacon(intention)

      if intent[:needs_mechanics]
        evaluations, world, capability = run_full_gate(intent)

        unless world[:consistent]
          @log.play_log!("world_check_failure", "SanityChecker world check failed: #{world[:reason]}")
          @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: world[:reason], dm_message: world[:dm_message] }
        end

        unless capability[:allowed]
          @log.play_log!("capability_rejection", "SanityChecker capability check failed: #{capability[:reason]}")
          @loop&.log_step("sanity_checker", "Capability check FAILED: #{capability[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: capability[:reason], dm_message: capability[:dm_message] }
        end

        @loop&.log_step("sanity_checker", "World: consistent")

        merged = merge_mechanical_evaluations(evaluations)
        warn_duplicate_rolls(merged)
        rolls_desc = merged[:player_rolls].map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }.join(", ")
        @loop&.log_step("mech_eval", rolls_desc.presence || "No rolls")
        filter_auto_success_rolls!(merged)

        if merged[:player_rolls].any?
          return { status: :awaiting_rolls, intent: intent, merged: merged }
        end

        return finish_resolution(intent, merged, auto_success_roll_message(merged))
      end

      world = run_world_consistency_check(intent)
      unless world[:consistent]
        @log.play_log!("world_check_failure", "SanityChecker world check failed: #{world[:reason]}")
        @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
        return { status: :rejected, intent: intent, reason: world[:reason], dm_message: world[:dm_message] }
      end

      @loop&.log_step("sanity_checker", "World: consistent (no mechanics)")

      if intent[:expand_scene]
        return resolve_social_scene(intent)
      end

      time_result = run_time_keeper(intent, nil)

      if time_result[:encounter]
        return maybe_warmaster_for_encounter(intent, time_result, mutations: nil)
      end

      momentum_result = run_momentum(intent)

      {
        status: :resolved, intent: intent,
        mutations: momentum_result[:mutations].presence,
        time_result: time_result
      }
    end

    # Post-roll completion: verdict → mutations → time_keeper
    def finish_resolution(intent, merged, roll_results)
      npc_results = resolve_npc_actions(merged[:npc_actions])
      verdict_result = run_mechanic(intent, merged, roll_results: roll_results, npc_results: npc_results)
      @loop&.batch_update!(
        new_data: { "verdict_outcome" => verdict_result[:outcome].to_s.truncate(500) },
        timeline_entry: { "step" => "mechanic", "summary" => verdict_result[:outcome].to_s.truncate(120), "at" => Time.current.iso8601 })
      apply_mutations(verdict_result[:mutations])

      time_result = run_time_keeper(intent, verdict_result)

      if time_result[:encounter]
        return maybe_warmaster_for_encounter(intent, time_result, mutations: verdict_result[:mutations])
      end

      store_pipeline_outcome!(verdict_result[:outcome])

      {
        status: :resolved, intent: intent,
        mutations: verdict_result[:mutations],
        time_result: time_result
      }
    end

    # Call Warmaster when Harbinger triggers an encounter (Path A).
    # Encounter data is read exclusively from @loop — set by Harbinger during TimeKeeper.
    def maybe_warmaster_for_encounter(intent, time_result, mutations:)
      entry_id = @loop&.get("encounter_entry_id")
      encounter_entry = EncounterTableEntry.find_by(id: entry_id) if entry_id

      if encounter_entry
        creatures_data = @loop&.get("encounter_creatures")
        warmaster_result = Utilities::Warmaster.initialize_from_encounter!(
          adventure: @adventure, encounter_entry: encounter_entry,
          creatures_data: creatures_data,
          sheet: @sheet, log: @log, config: @config, ai: @ai)

        if warmaster_result[:status] == :awaiting_initiative
          @loop&.batch_update!(
            new_tags: { "combat_started" => true },
            new_data: { "creature_count" => warmaster_result[:creature_data]&.size },
            timeline_entry: { "step" => "warmaster", "summary" => "Combat: #{warmaster_result[:creature_data]&.size} creature(s)", "at" => Time.current.iso8601 })

          encounter_scene = @loop&.get("encounter_scene")
          combined = [encounter_scene, @loop&.get("verdict_outcome")].compact.join("\n\n").presence
          store_pipeline_outcome!(combined)

          return {
            status: :awaiting_initiative, intent: intent,
            creature_data: warmaster_result[:creature_data],
            mutations: mutations, time_result: time_result
          }
        end
      end

      encounter_scene = @loop&.get("encounter_scene")
      combined = [encounter_scene, @loop&.get("verdict_outcome")].compact.join("\n\n").presence
      store_pipeline_outcome!(combined)

      { status: :encounter, intent: intent,
        mutations: mutations, time_result: time_result }
    end

    # Unified evaluation path: single AI call replaces beacons + mech eval + roll qualifier.
    # Sanity checks (world + capability) still run independently as guardrails.
    def resolve_unified(intention)
      intent, evaluations = run_unified_evaluation(intention)

      if intent[:needs_mechanics]
        world, capability = run_sanity_gate(intent)

        unless world[:consistent]
          @log.play_log!("world_check_failure", "SanityChecker world check failed: #{world[:reason]}")
          @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: world[:reason], dm_message: world[:dm_message] }
        end

        unless capability[:allowed]
          @log.play_log!("capability_rejection", "SanityChecker capability check failed: #{capability[:reason]}")
          @loop&.log_step("sanity_checker", "Capability check FAILED: #{capability[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: capability[:reason] }
        end

        @loop&.log_step("sanity_checker", "World: consistent")

        merged = merge_mechanical_evaluations(evaluations)
        warn_duplicate_rolls(merged)
        rolls_desc = merged[:player_rolls].map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }.join(", ")
        @loop&.log_step("mech_eval", rolls_desc.presence || "No rolls")
        filter_auto_success_rolls!(merged)

        if merged[:player_rolls].any?
          return { status: :awaiting_rolls, intent: intent, merged: merged }
        end

        return finish_resolution(intent, merged, auto_success_roll_message(merged))
      end

      world = run_world_consistency_check(intent)
      unless world[:consistent]
        @log.play_log!("world_check_failure", "SanityChecker world check failed: #{world[:reason]}")
        @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
        return { status: :rejected, intent: intent, reason: world[:reason], dm_message: world[:dm_message] }
      end

      @loop&.log_step("sanity_checker", "World: consistent (no mechanics)")

      if intent[:expand_scene]
        return resolve_social_scene(intent)
      end

      time_result = run_time_keeper(intent, nil)

      if time_result[:encounter]
        return maybe_warmaster_for_encounter(intent, time_result, mutations: nil)
      end

      momentum_result = run_momentum(intent)

      {
        status: :resolved, intent: intent,
        mutations: momentum_result[:mutations].presence,
        time_result: time_result
      }
    end

    def auto_success_roll_message(merged)
      descs = (merged[:auto_successes] || []).map { |s| "AUTO-SUCCESS: #{s}" }
      descs.any? ? descs.join("\n") : nil
    end

    # Social scene expansion: creates an immersive NPC interaction scene that
    # pauses the pipeline for player input. Analogous to encounter expansion
    # but for significant social interactions (transactions, negotiations, etc.).
    # TimeKeeper is skipped — no time passes until the interaction resolves.
    def resolve_social_scene(intent)
      prompt_summary = "SocialExpansion: \"#{@log.truncate(intent[:intention])}\""

      social_beacon = intent.dig(:beacon_results, "social") || {}
      npc_names = begin
        @adventure.story.story_npcs.pluck(:name)
      rescue => e
        pipeline_error!("social_expansion_npcs", e)
      end

      system_prompt = PromptRenderer.render("social_expansion",
        intention: intent[:intention],
        location: @adventure.current_location&.name || "the area",
        social_context: @adventure.social_context,
        character_block: CharacterBlock.full(@sheet),
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

    # Parallel world + capability checks without mech eval (used by unified path).
    def run_sanity_gate(intent)
      world = nil
      capability = nil

      world_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { world = run_world_consistency_check(intent) }
      end
      cap_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { capability = run_capability_check(intent) }
      end

      world_thread.value
      cap_thread.value

      [world, capability]
    end

    def store_pipeline_outcome!(text)
      if text.blank?
        @log&.play_log!("empty_pipeline_outcome", "Terminal wrote blank pipeline_outcome — narration context will be missing")
      end
      @loop&.batch_update!(new_data: { "pipeline_outcome" => text.to_s.truncate(2000) })
    end
  end
end
