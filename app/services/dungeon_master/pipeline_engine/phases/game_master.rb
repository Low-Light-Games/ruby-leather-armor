# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    module Phases
      # Conditional outer phase: when the user has the
      # gamemaster_orchestrator feature flag on AND combat is not active,
      # the GameMaster step owns the turn end-to-end and the legacy
      # OrchestrateCompoundActions phase is bypassed.
      class GameMaster
        def self.call(pipeline_engine, state)
          return { halt: false } unless pipeline_engine.use_game_master?

          clean_input = state.fetch(:clean_input)
          { halt: true, result: pipeline_engine.send(:run_game_master, clean_input) }
        end
      end
    end
  end
end
