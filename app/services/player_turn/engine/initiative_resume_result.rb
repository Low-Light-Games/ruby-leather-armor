# frozen_string_literal: true

module PlayerTurn
  class Engine
    class InitiativeResumeResult
      def initialize(intent:, mutations:, opener_outcome:)
        @intent = intent
        @mutations = mutations
        @opener_outcome = opener_outcome
      end

      def to_h
        {
          status: :resolved,
          intent: @intent,
          mutations: @mutations,
          action_outcome: @opener_outcome,
          precombat_opener: @opener_outcome.present?
        }
      end
    end
  end
end
