# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    module Phases
      class DmQueryBranch
        # @param state [Hash] must include :clean_input, :intake_result; optional :prompt_mode
        # @return [Hash] :halt => true, :result => dm_query hash — or — :halt => false
        def self.call(pipeline_engine, state)
          clean_input = state.fetch(:clean_input)
          prompt_mode = state[:prompt_mode]
          intake_result = state.fetch(:intake_result)

          if prompt_mode == "dm_query" || intake_result[:is_dm_query]
            return({ halt: true, result: pipeline_engine.send(:run_dm_query_flow, clean_input) })
          end

          { halt: false }
        end
      end
    end
  end
end
