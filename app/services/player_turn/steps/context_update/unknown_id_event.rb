# frozen_string_literal: true

module PlayerTurn
  module Steps
    module ContextUpdate
      class UnknownIdEvent
        attr_reader :requested_id, :roster_ids, :hp_delta, :added, :removed

        def initialize(requested_id:, roster_ids:, hp_delta:, added:, removed:)
          @requested_id = requested_id
          @roster_ids   = Array(roster_ids)
          @hp_delta     = hp_delta
          @added        = Array(added)
          @removed      = Array(removed)
        end

        def to_h
          {
            requested_id: @requested_id,
            roster_ids:   @roster_ids,
            hp_delta:     @hp_delta,
            added:        @added,
            removed:      @removed,
          }
        end
      end
    end
  end
end
