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
            affected_contexts: Array(@prior_intent[:affected_contexts]),
            macro_significant: @prior_intent[:macro_significant] == true,
            domain_results: @prior_intent[:domain_results].is_a?(Hash) ? @prior_intent[:domain_results] : {}
          },
          mutations: {},
          action_outcome: @action_outcome
        }
      end
    end
  end
end
