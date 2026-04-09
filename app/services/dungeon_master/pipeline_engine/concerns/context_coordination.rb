# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    module Concerns
      # Steps::ContextUpdate orchestration between queued actions and at encounter → initiative pause.
      module ContextCoordination
        private

        def run_inter_action_context_update(result)
          outcome = current_loop_pipeline_outcome
          return if outcome.blank?

          run_context_updates(outcome, result[:mutations])
          @adventure.reload
          @loop&.batch_update!(
            timeline_entry: tl("inter_action_ctx", "Micro contexts updated between actions"))
        end

        # Encounter → initiative pause: refresh contexts from the encounter outcome (see ContextUpdatePause).
        def run_context_updates_at_encounter_pause(mutations)
          outcome = current_loop_pipeline_outcome
          return if outcome.blank?

          run_context_updates(outcome, mutations)
        rescue => e
          @log.log!(:warn, "[encounter_pause_ctx_update] #{e.class}: #{e.message}")
        end

        def current_loop_pipeline_outcome
          @loop&.get("pipeline_outcome")
        end
      end
    end
  end
end
