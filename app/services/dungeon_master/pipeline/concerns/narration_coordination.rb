# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    module Concerns
      # Wires Narrative::*Assembly + Stagehand narrate; progressive +on_narrative+ payloads.
      # See also Pipeline::Concerns::EntryPoints and action_queue_runner.rb.
      module NarrationCoordination
        PROGRESSIVE_QUEUE_MODES = %w[progressive progressive_continuity].freeze

        private

        def run_accumulated_narrative_phase(results)
          return { action: :narrated, narrative: "", adventure_complete: false } if results.empty?

          narration_inputs = Narrative::AccumulatedAssembly.call(pipeline: self, results: results)
          run_narrative_phase(narration_inputs.merged_intent,
            pipeline: narration_inputs.pipeline_context,
            mutations: narration_inputs.mutations,
            extra: narration_inputs.extra)
        end

        def run_single_action_narrative_phase(result, sequence_index, total_actions)
          narration_inputs = Narrative::SingleActionAssembly.call(
            pipeline: self,
            result: result,
            progressive_continuity: action_queue_continuity?)

          phase = run_narrative_phase(narration_inputs.intent,
            pipeline: narration_inputs.pipeline_context,
            mutations: narration_inputs.mutations)

          entry = Narrative::ProgressiveEntry.from_narrative_phase(
            phase,
            sequence_index: sequence_index,
            total_actions: total_actions,
            action_text: narration_inputs.pipeline_context.player_action&.truncate(200))

          payload = entry.to_h
          @on_narrative&.call(payload)
          payload
        end

        def action_queue_mode
          @adventure.effective_dm_setting("action_queue")
        end

        def per_action_narration?
          PROGRESSIVE_QUEUE_MODES.include?(action_queue_mode)
        end

        def action_queue_continuity?
          action_queue_mode == "progressive_continuity"
        end
      end
    end
  end
end
