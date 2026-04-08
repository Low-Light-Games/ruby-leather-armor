# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    module Phases
      # Sequencer → action queue loop (ActionQueueRunner) → narrative phase.
      #
      # Assumes:
      #   - clean_input string; pipeline mixins for Sequencer + AdventureLoopResolution; @log.registry_entry_uuid.
      #
      # Sets:
      #   - @loop per action inside runner; AdventureLoops; final return from narrative phase.
      #
      # Prompts:
      #   - Sequencer when action_queue enabled; then all resolve/narration prompts via runner.
      class OrchestrateCompoundActions
        def self.call(pipeline_engine, state)
          clean_input = state.fetch(:clean_input)
          actions = pipeline_engine.send(:run_sequencer, clean_input)
          total = actions.size

          result = ActionQueueRunner.new(pipeline_engine).run(
            action_strings: actions,
            base_sequence_index: 0,
            total_for_logging: total,
            abort_on_rejected: true,
            per_action_narration: pipeline_engine.send(:per_action_narration?) && total > 1
          )
          { halt: true, result: result }
        end
      end
    end
  end
end
