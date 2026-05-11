# frozen_string_literal: true

module PlayerTurn
  class Engine
    class AwaitingRollsResumePayload
      def initialize(intent:, merged:, remaining_actions:)
        @intent = intent
        @merged = merged
        @remaining_actions = remaining_actions
      end

      def to_h
        {
          action: :awaiting_rolls,
          intent: @intent,
          merged: @merged,
          remaining_actions: @remaining_actions
        }
      end
    end
  end
end
