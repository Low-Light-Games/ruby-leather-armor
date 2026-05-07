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
          result = pipeline_engine.send(:run_game_master, clean_input)

          if result[:action] == :game_master_pending_tools
            result = pipeline_engine.send(:dispatch_game_master_tools, result)
          end

          { halt: true, result: result }
        end
      end
    end
  end
end
