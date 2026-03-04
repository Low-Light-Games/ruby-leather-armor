# frozen_string_literal: true

module DungeonMaster
  # Inner pipeline: resolves a single player action from dispatch through time_keeper.
  #
  # Extracted from Pipeline's run_action_flow / run_resolution_flow so the
  # outer orchestrator (orchestrate_actions) can loop over queued actions
  # without duplicating resolution logic.
  #
  # Returns a standardized result hash with :status indicating the outcome:
  #   :resolved        — action fully resolved, narrate_seed and mutations available
  #   :awaiting_rolls  — rolls needed, intent and merged available for resumption
  #   :encounter       — Harbinger triggered an encounter mid-action
  #   :rejected        — CapabilityGuardrail rejected the action
  module CoreResolver
    private

    # Full resolution: beacon → mechanics gate → [verdict + mutations + time_keeper]
    def resolve(intention, category)
      intent = run_beacon(intention, category)

      if intent[:needs_mechanics]
        evaluations, guardrail = run_mechanics_gate(intent)

        unless guardrail[:allowed]
          @log.dm_log!("CapabilityGuardrail rejected: #{guardrail[:reason]}")
          return { status: :rejected, intent: intent, reason: guardrail[:reason] }
        end

        merged = merge_mechanical_evaluations(evaluations)
        filter_auto_success_rolls!(merged)

        if merged[:player_rolls].any?
          return { status: :awaiting_rolls, intent: intent, merged: merged }
        end

        return finish_resolution(intent, merged, "(no player rolls required)")
      end

      time_result = run_time_keeper(intent, nil)

      if time_result[:encounter]
        return {
          status: :encounter, intent: intent,
          narrate_seed: time_result[:encounter_narrative],
          mutations: nil, time_result: time_result
        }
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
        return {
          status: :encounter, intent: intent,
          narrate_seed: time_result[:encounter_narrative],
          mutations: verdict_result[:mutations],
          time_result: time_result
        }
      end

      {
        status: :resolved, intent: intent,
        narrate_seed: verdict_result[:outcome],
        mutations: verdict_result[:mutations],
        time_result: time_result
      }
    end
  end
end
