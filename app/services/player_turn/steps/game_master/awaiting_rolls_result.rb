# frozen_string_literal: true

module PlayerTurn
  module Steps
    module GameMaster
      class AwaitingRollsResult
        def initialize(intent:, merged_pause_state:, lead_narrative:)
          @intent = intent
          @merged_pause_state = merged_pause_state
          @lead_narrative = lead_narrative
        end

        def to_h
          {
            action: :awaiting_rolls,
            intent: @intent,
            merged: @merged_pause_state.to_h,
            remaining_actions: [],
            game_master_narrative: @lead_narrative
          }
        end
      end
    end
  end
end
