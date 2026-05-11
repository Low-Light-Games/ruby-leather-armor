# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatRollRequest
      class TimelineEntry
        STEP = 'combat_roll_request'

        # @param rolls_desc [String]
        def initialize(rolls_desc:)
          @rolls_desc = rolls_desc
        end

        def to_h
          {
            'step' => STEP,
            'summary' => @rolls_desc.presence || 'No rolls',
            'at' => Time.current.iso8601
          }
        end
      end
    end
  end
end
