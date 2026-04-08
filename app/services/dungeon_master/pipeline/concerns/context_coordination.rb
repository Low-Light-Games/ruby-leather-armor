# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    module Concerns
      # Steps::ContextUpdate orchestration between queued actions and at encounter → initiative pause.
      module ContextCoordination
        private

        def run_inter_action_context_update(result)
          outcome = @loop&.get("pipeline_outcome")
          return unless outcome.present?

          run_context_updates(outcome, result[:mutations])
          @adventure.reload
          @loop&.batch_update!(
            timeline_entry: tl("inter_action_ctx", "Micro contexts updated between actions"))
        end

        # Roll-request pauses: see DungeonMaster::ContextUpdatePause.

        # Run ContextUpdate before an initiative-pause from a Harbinger encounter.
        # The encounter scene is the outcome — contexts reflect combat beginning
        # before the player rolls initiative.
        def run_context_updates_at_encounter_pause(mutations)
          encounter_outcome = @loop&.get("pipeline_outcome")
          return unless encounter_outcome.present?
          run_context_updates(encounter_outcome, mutations)
        rescue => e
          @log.log!(:warn, "[encounter_pause_ctx_update] #{e.class}: #{e.message}")
        end
      end
    end
  end
end
