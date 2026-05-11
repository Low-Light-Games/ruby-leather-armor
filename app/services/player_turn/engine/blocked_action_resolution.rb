# frozen_string_literal: true

module PlayerTurn
  class Engine
    class BlockedActionResolution
      def initialize(action_text:, action_outcome:)
        @action_text = action_text
        @action_outcome = action_outcome
      end

      def to_h
        {
          status: :resolved,
          intent: {
            intention: @action_text,
          },
          mutations: {},
          action_outcome: @action_outcome
        }
      end
    end
  end
end
