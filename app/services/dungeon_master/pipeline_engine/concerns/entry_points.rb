# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    module Concerns
      # Public resume/run API, prompt phase chain, DM-query branch, mid-queue continuation.
      #
      # run_initiative notes:
      #   - PersistCombatStart atomically archives stale battlefields and creates a fresh one.
      #   - When NPCs outroll the player (current_turn != "Player"), maybe_run_world_turn fires
      #     before any remaining actions. result[:mutations] is enriched by world turn.
      #   - The remaining queue is skipped entirely when result[:player_death] or
      #     result[:player_incapacitated] — terminal_combat_result? guards both branches.
      #   - Post-world-turn mutations (result[:mutations]) are always forwarded to
      #     run_remaining_queue; never the pre-world-turn base_mutations.
      #
      # run_rolls notes:
      #   - continue_or_narrate_after_resume also checks terminal_combat_result? before
      #     running the remaining queue, so run_rolls cannot continue a queue after a lethal
      #     world turn triggered by finish_resolution.
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
            request: Utilities::Warmaster::CombatInitializationRequest.new(
              adventure: @adventure,
              player_sheet: @sheet,
              creature_data: creature_data.map(&:deep_symbolize_keys),
              player_initiative: player_initiative
            )
          )

          intent = metadata["intent"]&.deep_symbolize_keys
          raise AiError, "Initiative metadata missing intent — state integrity failure" unless intent

          # Atomic combat start: battlefield row + battlefield_ref + action_economy in one transaction.
          Battlefield::PersistCombatStart.call(adventure: @adventure, combat_data: combat_data, sheet: @sheet)
          @adventure.reload

          base_mutations = metadata["mutations"] || {}
          opener_outcome = metadata["opener_outcome"].to_s.presence
          result = {
            status: :resolved,
            intent: intent,
            mutations: base_mutations,
            action_outcome: opener_outcome,
            precombat_opener: opener_outcome.present?
          }
          opening_merged = restore_opening_action_merged(metadata)

          if opening_merged
            if opening_merged[:player_rolls].any?
              @loop&.batch_update!(new_status: "paused",
                timeline_entry: tl("awaiting_rolls", "Paused for player rolls"))
              ContextUpdatePause.run(pipeline_engine: self, intent: intent, merged: opening_merged)
              return {
                action: :awaiting_rolls,
                intent: intent,
                merged: opening_merged,
                remaining_actions: remaining_actions_from(metadata)
              }
            end

            opening_result = finish_resolution(intent, opening_merged, Rolls::PlayerRolls.auto_success_roll_message(opening_merged))
            return continue_or_narrate_after_resume(metadata, accumulated_row: opening_result, only_continue_if_resolved: true)
          end

          # If any NPC outrolled the player on initiative, they act now — before the player's
          # first move. World turn enriches result[:mutations] with combat advancement and sets
          # :player_death / :player_incapacitated on the result when needed.
          npcs_go_first = combat_data["current_turn"] != Utilities::CombatTurnCalculator::PLAYER_NAME
          if npcs_go_first && opener_outcome.present? && opening_merged.blank?
            @loop&.batch_update!(new_data: { "pipeline_outcome" => "" })
          end
          result = maybe_run_world_turn(result) if npcs_go_first

          remaining = remaining_actions_from(metadata)
          if remaining.any? && !terminal_combat_result?(result)
            # Use post-world-turn mutations so combat advancement carries through the queue.
            run_remaining_queue(remaining, initial_accumulated: [result])
          elsif npcs_go_first || terminal_combat_result?(result)
            # World turn appended NPC action prose to pipeline_outcome; narrate it so
            # the player sees what the enemies did before their first move.
            run_accumulated_narrative_phase([result])
          else
            {
              action: :combat_initialized,
              combat_start_message: player_turn_combat_start_message(combat_data)
            }.merge(result.slice(:player_death, :player_incapacitated))
          end
        end

        def run_rolls(roll_results, metadata, submitted_rolls: nil)
          restore_paused_loop!

          if battlefield_roll_version_mismatch?(metadata)
            row = @adventure.adventure_battlefields.find_by(id: metadata["battlefield_id"].to_i)
            @log.play_log!(
              "battlefield_version_mismatch",
              "Roll request battlefield snapshot stale — metadata v#{metadata['battlefield_version']} vs row v#{row&.version}",
              parsed_response: {
                battlefield_id: metadata["battlefield_id"],
                expected_version: metadata["battlefield_version"],
                actual_version: row&.version
              }
            )
            return {
              action: :battlefield_version_mismatch,
              message: "Combat map changed since these rolls were requested. Submit again using the updated prompt."
            }
          end

          Rolls::PlayerRolls.tag_roll_resolution!(@loop, roll_results)

          intent, merged = restore_roll_pause_inputs(metadata)
          restored_roll_requests = Array(metadata["roll_requests"]).map(&:deep_symbolize_keys)
          result = finish_resolution(intent, merged, roll_results,
            requested_rolls: restored_roll_requests,
            submitted_rolls: submitted_rolls)

          if result[:status] == :awaiting_rolls
            @loop&.batch_update!(new_status: "paused",
              timeline_entry: tl("awaiting_rolls", "Paused for player rolls"))
            ContextUpdatePause.run(pipeline_engine: self, intent: result[:intent], merged: result[:merged])
            return {
              action: :awaiting_rolls,
              intent: result[:intent],
              merged: result[:merged],
              remaining_actions: result[:remaining_actions] || remaining_actions_from(metadata)
            }
          end

          if result[:status] == :awaiting_initiative
            @loop&.batch_update!(new_status: "paused",
              new_tags: { "combat_started" => true },
              timeline_entry: tl("awaiting_initiative", "Paused for player initiative"))
            run_context_updates_at_encounter_pause(result[:mutations])
            return {
              action: :awaiting_initiative,
              intent: result[:intent],
              creature_data: result[:creature_data],
              pending_opening_merged: result[:pending_opening_merged] || result[:merged],
              mutations: result[:mutations],
              remaining_actions: result[:remaining_actions] || remaining_actions_from(metadata)
            }
          end

          final_status = result[:status] == :encounter ? "encounter" : "resolved"
          @loop&.batch_update!(new_status: final_status,
            timeline_entry: tl("rolls_resolved", "Rolls submitted, status: #{final_status}"))

          continue_or_narrate_after_resume(metadata, accumulated_row: result, only_continue_if_resolved: true)
        end

        private

        # Fail closed when roll_request metadata carries a battlefield snapshot that no longer matches the row.
        # Uses the persisted snapshot only — not combat_active?, so stale roll resumes still guard after combat ends or context desync.
        def battlefield_roll_version_mismatch?(metadata)
          return false if metadata["battlefield_id"].blank?

          bid = metadata["battlefield_id"].to_i
          row = @adventure.adventure_battlefields.find_by(id: bid)
          return true unless row
          metadata["battlefield_version"].to_i != row.version.to_i
        end

        def remaining_actions_from(metadata)
          metadata["remaining_actions"] || []
        end

        def restore_opening_action_merged(metadata)
          raw = metadata["pending_opening_merged"]
          return nil unless raw.is_a?(Hash)

          merged = raw.deep_symbolize_keys
          merged[:player_rolls] = Array(merged[:player_rolls]).map(&:deep_symbolize_keys)
          merged[:npc_actions] = Array(merged[:npc_actions]).map(&:deep_symbolize_keys)
          merged[:consequences] = Array(merged[:consequences]).map(&:deep_symbolize_keys)
          merged[:mechanical_summaries] = Array(merged[:mechanical_summaries])
          merged
        end

        # After rolls/initiative resume: either run the rest of the queue or one accumulated narrate pass.
        # Never continues the queue when the player is dead or incapacitated — terminal state wins.
        def continue_or_narrate_after_resume(metadata, accumulated_row:, only_continue_if_resolved: false)
          remaining = remaining_actions_from(metadata)
          status = accumulated_row[:status]
          intent = accumulated_row[:intent]
          mutations = accumulated_row[:mutations]
          queue_allowed = remaining.any? &&
                          (!only_continue_if_resolved || status == :resolved) &&
                          !terminal_combat_result?(accumulated_row)
          if queue_allowed
            run_remaining_queue(remaining, initial_accumulated: [accumulated_row])
          else
            run_accumulated_narrative_phase([accumulated_row])
          end
        end

        def terminal_combat_result?(result)
          result[:player_death] || result[:player_incapacitated]
        end

        def player_turn_combat_start_message(combat_data)
          turn_order = Array(combat_data["turn_order"]).presence
          if turn_order
            "Combat begins. Turn order: #{turn_order.join(', ')}. It's your turn."
          else
            "Combat begins. It's your turn."
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
        def run_remaining_queue(remaining, initial_accumulated: [])
          processed_count = AdventureLoop.for_registry_entry(@log.registry_entry_uuid).count
          total_original = processed_count + remaining.size
          base_idx = processed_count
          ActionQueueRunner.new(self).run(
            action_strings: remaining,
            base_sequence_index: base_idx,
            total_for_logging: total_original,
            abort_on_rejected: false,
            initial_accumulated: initial_accumulated,
            per_action_narration: false
          )
        end
      end
    end
  end
end
