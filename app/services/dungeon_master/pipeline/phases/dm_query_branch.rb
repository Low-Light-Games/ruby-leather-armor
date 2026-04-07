# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    module Phases
      # Routes Ask DM mode / classified DM queries to the fast DM answer path.
      #
      # Assumes:
      #   - clean_input from intake; mode from run_prompt; @adventure, @log, @ai, etc.
      #
      # Sets:
      #   - None beyond DM query AI logs and any plot stub side effects in resolve_plot path.
      #
      # Prompts:
      #   - resolve_plot (chronicler path when story has plot data), run_dm_query.
      class DmQueryBranch
        # @param state [Hash] must include :clean_input, :intake_result; optional :mode
        # @return [Hash] :halt => true, :result => dm_query hash — or — :halt => false
        def self.call(pipeline, state)
          clean_input = state.fetch(:clean_input)
          mode = state[:mode]
          intake_result = state.fetch(:intake_result)

          if mode == "dm_query" || intake_result[:is_dm_query]
            return({ halt: true, result: pipeline.send(:run_dm_query_flow, clean_input) })
          end

          { halt: false }
        end
      end
    end
  end
end
