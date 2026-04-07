# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    module Phases
      # Sequencer → action queue loop (ActionQueueRunner) → narrative phase.
      #
      # Assumes:
      #   - clean_input string; pipeline mixins for Sequencer + CoreResolver; @log.pipeline_run_id.
      #
      # Sets:
      #   - @loop per action inside runner; AdventureLoops; final return from narrative phase.
      #
      # Prompts:
      #   - Sequencer when action_queue enabled; then all resolve/narration prompts via runner.
      class OrchestrateCompoundActions
        def self.call(pipeline, state)
          clean_input = state.fetch(:clean_input)
          actions = pipeline.send(:run_sequencer, clean_input)
          total = actions.size

          result = ActionQueueRunner.new(pipeline).run(
            action_strings: actions,
            base_sequence_index: 0,
            total_for_logging: total,
            abort_on_rejected: true,
            per_action_narration: pipeline.send(:per_action_narration?) && total > 1
          )
          { halt: true, result: result }
        end
      end
    end
  end
end
