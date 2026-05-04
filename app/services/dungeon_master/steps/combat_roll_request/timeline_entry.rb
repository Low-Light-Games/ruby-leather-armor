# frozen_string_literal: true

module DungeonMaster
  module Steps
    module CombatRollRequest
      # AdventureLoop timeline row recorded after a combat roll request
      # resolves. Persisted as a Hash entry on the loop's timeline JSONB column.
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
