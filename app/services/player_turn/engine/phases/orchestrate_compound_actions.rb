# frozen_string_literal: true

module PlayerTurn
  class Engine
    module Phases
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
