# frozen_string_literal: true

module DungeonMaster
  module Steps
    module CombatRollRequest
      # AdventureLoop timeline row recorded after a combat roll request
      # resolves — names the step, summarizes affected contexts +
      # rolls, stamps the time. Persisted as a Hash entry on the loop's
      # timeline JSONB column.
      class TimelineEntry
        STEP = 'combat_roll_request'

        # @param affected [Array<String>]
        # @param rolls_desc [String]
        def initialize(affected:, rolls_desc:)
          @affected = affected
          @rolls_desc = rolls_desc
        end

        def to_h
          {
            'step' => STEP,
            'summary' => summary,
            'at' => Time.current.iso8601
          }
        end

        private

        def summary
          [
            "Affected: #{@affected.join(', ').presence || 'none'}",
            @rolls_desc.presence || 'No rolls'
          ].join(' | ')
        end
      end
    end
  end
end
