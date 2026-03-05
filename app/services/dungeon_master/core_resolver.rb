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
      intent = run_beacon(intention, category)

      if intent[:needs_mechanics]
        evaluations, world, capability = run_full_gate(intent)

        unless world[:consistent]
          @log.dm_log!("SanityChecker world check failed: #{world[:reason]}")
          return { status: :rejected, intent: intent, reason: world[:reason] }
        end

        unless capability[:allowed]
          @log.dm_log!("SanityChecker capability check failed: #{capability[:reason]}")
          return { status: :rejected, intent: intent, reason: capability[:reason] }
        end

        merged = merge_mechanical_evaluations(evaluations)
        filter_auto_success_rolls!(merged)

        if merged[:player_rolls].any?
          return { status: :awaiting_rolls, intent: intent, merged: merged }
        end

        return finish_resolution(intent, merged, "(no player rolls required)")
      end

      world = run_world_consistency_check(intent)
      unless world[:consistent]
        @log.dm_log!("SanityChecker world check failed: #{world[:reason]}")
        return { status: :rejected, intent: intent, reason: world[:reason] }
      end

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

    # Call Warmaster when Harbinger triggers an encounter (Path A)
    def maybe_warmaster_for_encounter(intent, time_result, mutations:)
      encounter_entry = time_result.dig(:encounter_entry)

      if encounter_entry
        warmaster_result = Utilities::Warmaster.initialize_from_encounter!(
          adventure: @adventure, encounter_entry: encounter_entry,
          sheet: @sheet, log: @log, config: @config, ai: @ai)

        if warmaster_result[:status] == :awaiting_initiative
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
  end
end
