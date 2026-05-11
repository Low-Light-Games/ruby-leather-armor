# frozen_string_literal: true

module PlayerTurn
  module Steps
    module RollRequest
      class UnknownTargetEvent
        attr_reader :emitted_target_id, :roster_ids, :roster_names

        def initialize(emitted_target_id:, roster_ids:, roster_names:)
          @emitted_target_id = emitted_target_id
          @roster_ids        = Array(roster_ids)
          @roster_names      = Array(roster_names)
        end

        def to_h
          {
            emitted_target_id: @emitted_target_id,
            roster_ids:        @roster_ids,
            roster_names:      @roster_names,
          }
        end
      end
    end
  end
end
