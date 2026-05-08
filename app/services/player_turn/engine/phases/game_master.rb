# frozen_string_literal: true

module PlayerTurn
  class Engine
    module Phases
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
