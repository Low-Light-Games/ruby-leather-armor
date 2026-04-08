# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    module Concerns
      # Public resume/run API, prompt phase chain, DM-query branch, mid-queue continuation.
      module EntryPoints
        def run_prompt(player_input, mode: nil)
          state = { player_input: player_input, mode: mode }
          # Assign then return — avoid `return r if (r = …)` (parses as `return (r if …)` and can raise NameError on `r`).
          result = apply_prompt_phase(Phases::IntakeDangerGate, state)
          return result if result
          result = apply_prompt_phase(Phases::DmQueryBranch, state)
          return result if result
          apply_prompt_phase(Phases::OrchestrateCompoundActions, state) || raise("run_prompt: terminal phase did not halt")
        end

        def run_initiative(player_initiative, metadata)
          restore_paused_loop!
          @loop&.batch_update!(new_status: "resolved",
            timeline_entry: tl("initiative_resolved", "Player initiative: #{player_initiative}"))

          creature_data = metadata["creature_data"] || []
          combat_data = Utilities::Warmaster.compute_combat_initialization(
            creature_data: creature_data.map(&:deep_symbolize_keys),
            player_initiative: player_initiative)

          intent = metadata["intent"]&.deep_symbolize_keys
          raise AiError, "Initiative metadata missing intent — state integrity failure" unless intent
          base_mutations = metadata["mutations"] || {}
          mutations = base_mutations.merge("combat_initialization" => combat_data)
          continue_or_narrate_after_resume(
            metadata,
            accumulated_row: { status: :encounter, intent: intent, mutations: mutations })
        end

        def run_rolls(roll_results, metadata)
          restore_paused_loop!
          Rolls::PlayerRolls.tag_roll_resolution!(@loop, roll_results)

          intent, merged = restore_roll_pause_inputs(metadata)
          result = finish_resolution(intent, merged, roll_results)

          if result[:status] == :awaiting_initiative
            @loop&.batch_update!(new_status: "paused",
              new_tags: { "combat_started" => true },
              timeline_entry: tl("awaiting_initiative", "Paused for player initiative"))
            run_context_updates_at_encounter_pause(result[:mutations])
            return {
              action: :awaiting_initiative,
              intent: result[:intent],
              creature_data: result[:creature_data],
              mutations: result[:mutations],
              remaining_actions: remaining_actions_from(metadata)
            }
          end

          final_status = result[:status] == :encounter ? "encounter" : "resolved"
          @loop&.batch_update!(new_status: final_status,
            timeline_entry: tl("rolls_resolved", "Rolls submitted, status: #{final_status}"))

          continue_or_narrate_after_resume(metadata, accumulated_row: result, only_continue_if_resolved: true)
        end

        private

        def remaining_actions_from(metadata)
          metadata["remaining_actions"] || []
        end

        # After rolls/initiative resume: either run the rest of the queue or one accumulated narrate pass.
        def continue_or_narrate_after_resume(metadata, accumulated_row:, only_continue_if_resolved: false)
          remaining = remaining_actions_from(metadata)
          status = accumulated_row[:status]
          intent = accumulated_row[:intent]
          mutations = accumulated_row[:mutations]
          if remaining.any? && (!only_continue_if_resolved || status == :resolved)
            run_remaining_queue(remaining,
              accumulated_intents: [intent],
              accumulated_mutations: [mutations].compact)
          else
            run_accumulated_narrative_phase([accumulated_row])
          end
        end

        def apply_prompt_phase(phase, state)
          out = phase.call(self, state)
          state.merge!(out.except(:halt, :result))
          out[:halt] ? out[:result] : nil
        end

        # Assumes: clean_input from intake; @adventure, @log, @ai; optional plot data for chronicler stub.
        # Prompts: resolve_plot (conditional), run_dm_query.
        def run_dm_query_flow(clean_input)
          intent_stub = { intention: clean_input, affected_contexts: [], macro_significant: false }
          plot_result = resolve_plot(intent_stub)
          dm_brief = plot_result&.dig(:dm_brief)
          forbidden_elements = plot_result&.dig(:forbidden_elements) || []

          result = run_dm_query(clean_input, dm_brief: dm_brief, forbidden_elements: forbidden_elements)
          { action: :dm_query, answer: result[:answer] }
        end

        # Continue the action queue after a roll pause or from a mid-queue resume.
        # :rejected on an action skips that action (next); fresh orchestration aborts the whole turn instead.
        def run_remaining_queue(remaining, accumulated_intents: [], accumulated_mutations: [])
          processed_count = AdventureLoop.for_registry_entry(@log.registry_entry_uuid).count
          total_original = processed_count + remaining.size
          base_idx = processed_count
          accumulated = accumulated_intents.each_with_index.map do |intent, i|
            { status: :resolved, intent: intent, mutations: accumulated_mutations[i] }
          end

          ActionQueueRunner.new(self).run(
            action_strings: remaining,
            base_sequence_index: base_idx,
            total_for_logging: total_original,
            abort_on_rejected: false,
            initial_accumulated: accumulated,
            per_action_narration: false
          )
        end
      end
    end
  end
end
