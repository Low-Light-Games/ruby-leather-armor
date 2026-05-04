# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    class BlockedActionResolution
      def initialize(action_text:, prior_intent:, action_outcome:)
        @action_text = action_text
        @prior_intent = prior_intent.is_a?(Hash) ? prior_intent.deep_dup : {}
        @action_outcome = action_outcome
      end

      def to_h
        {
          status: :resolved,
          intent: {
            intention: @action_text,
            macro_significant: @prior_intent[:macro_significant] == true
          },
          mutations: {},
          action_outcome: @action_outcome
        }
      end
    end
  end
end
