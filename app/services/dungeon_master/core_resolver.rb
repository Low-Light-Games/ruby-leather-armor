# frozen_string_literal: true

module DungeonMaster
  # Inner pipeline: resolves a single player action from dispatch through time_keeper.
  #
  # Extracted from Pipeline's run_action_flow / run_resolution_flow so the
  # outer orchestrator (orchestrate_actions) can loop over queued actions
  # without duplicating resolution logic.
  #
  # Returns a standardized result hash with :status indicating the outcome:
  #   :resolved             — action fully resolved, narrate_seed and mutations available
  #   :awaiting_rolls       — rolls needed, intent and merged available for resumption
  #   :awaiting_initiative  — combat starting, waiting for player initiative roll
  #   :encounter            — Harbinger triggered an encounter mid-action
  #   :rejected             — SanityChecker rejected the action
  module CoreResolver
    private

    # Full resolution: beacon → full gate (mech eval + world check + cap check) → [verdict + mutations + time_keeper]
    def resolve(intention, category)
      if @config.get("evaluation_mode") == "unified"
        return resolve_unified(intention, category)
      end

      intent = run_beacon(intention, category)

      if intent[:needs_mechanics]
        evaluations, world, capability = run_full_gate(intent)

        unless world[:consistent]
          @log.dm_log!("SanityChecker world check failed: #{world[:reason]}")
          @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: world[:reason] }
        end

        unless capability[:allowed]
          @log.dm_log!("SanityChecker capability check failed: #{capability[:reason]}")
          @loop&.log_step("sanity_checker", "Capability check FAILED: #{capability[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: capability[:reason] }
        end

        @loop&.log_step("sanity_checker", "World: consistent")

        merged = merge_mechanical_evaluations(evaluations)
        deduplicate_rolls!(merged)
        rolls_desc = merged[:player_rolls].map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }.join(", ")
        @loop&.log_step("mech_eval", rolls_desc.presence || "No rolls")
        filter_auto_success_rolls!(merged)

        if merged[:player_rolls].any?
          return { status: :awaiting_rolls, intent: intent, merged: merged }
        end

        return finish_resolution(intent, merged, "(no player rolls required)")
      end

      world = run_world_consistency_check(intent)
      unless world[:consistent]
        @log.dm_log!("SanityChecker world check failed: #{world[:reason]}")
        @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
        return { status: :rejected, intent: intent, reason: world[:reason] }
      end

      @loop&.log_step("sanity_checker", "World: consistent (no mechanics)")

      time_result = run_time_keeper(intent, nil)

      if time_result[:encounter]
        return maybe_warmaster_for_encounter(intent, time_result, mutations: nil)
      end

      {
        status: :resolved, intent: intent,
        narrate_seed: nil, mutations: nil,
        time_result: time_result
      }
    end

    # Post-roll completion: verdict → mutations → time_keeper
    def finish_resolution(intent, merged, roll_results)
      npc_results = resolve_npc_actions(merged[:npc_actions])
      verdict_result = run_verdict(intent, merged, roll_results: roll_results, npc_results: npc_results)
      @loop&.batch_update!(
        new_data: { "verdict_outcome" => verdict_result[:outcome].to_s.truncate(500) },
        timeline_entry: { "step" => "verdict", "summary" => verdict_result[:outcome].to_s.truncate(120), "at" => Time.current.iso8601 })
      apply_mutations(verdict_result[:mutations])

      time_result = run_time_keeper(intent, verdict_result)

      if time_result[:encounter]
        return maybe_warmaster_for_encounter(intent, time_result, mutations: verdict_result[:mutations])
      end

      {
        status: :resolved, intent: intent,
        narrate_seed: verdict_result[:outcome],
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

          return {
            status: :awaiting_initiative, intent: intent,
            creature_data: warmaster_result[:creature_data],
            narrate_seed: time_result[:encounter_narrative],
            mutations: mutations, time_result: time_result
          }
        end
      end

      { status: :encounter, intent: intent,
        narrate_seed: time_result[:encounter_narrative],
        mutations: mutations, time_result: time_result }
    end

    # Unified evaluation path: single AI call replaces beacons + mech eval + roll qualifier.
    # Sanity checks (world + capability) still run independently as guardrails.
    def resolve_unified(intention, category)
      intent, evaluations = run_unified_evaluation(intention, category)

      if intent[:needs_mechanics]
        world, capability = run_sanity_gate(intent)

        unless world[:consistent]
          @log.dm_log!("SanityChecker world check failed: #{world[:reason]}")
          @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: world[:reason] }
        end

        unless capability[:allowed]
          @log.dm_log!("SanityChecker capability check failed: #{capability[:reason]}")
          @loop&.log_step("sanity_checker", "Capability check FAILED: #{capability[:reason].to_s.truncate(100)}")
          return { status: :rejected, intent: intent, reason: capability[:reason] }
        end

        @loop&.log_step("sanity_checker", "World: consistent")

        merged = merge_mechanical_evaluations(evaluations)
        deduplicate_rolls!(merged)
        rolls_desc = merged[:player_rolls].map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }.join(", ")
        @loop&.log_step("mech_eval", rolls_desc.presence || "No rolls")
        filter_auto_success_rolls!(merged)

        if merged[:player_rolls].any?
          return { status: :awaiting_rolls, intent: intent, merged: merged }
        end

        return finish_resolution(intent, merged, "(no player rolls required)")
      end

      world = run_world_consistency_check(intent)
      unless world[:consistent]
        @log.dm_log!("SanityChecker world check failed: #{world[:reason]}")
        @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
        return { status: :rejected, intent: intent, reason: world[:reason] }
      end

      @loop&.log_step("sanity_checker", "World: consistent (no mechanics)")

      time_result = run_time_keeper(intent, nil)

      if time_result[:encounter]
        return maybe_warmaster_for_encounter(intent, time_result, mutations: nil)
      end

      {
        status: :resolved, intent: intent,
        narrate_seed: nil, mutations: nil,
        time_result: time_result
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
  end
end
