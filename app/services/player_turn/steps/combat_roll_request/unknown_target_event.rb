# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatRollRequest
      class UnknownTargetEvent
        attr_reader :requested_id, :valid_ids

        def initialize(requested_id:, valid_ids:)
          @requested_id = requested_id
          @valid_ids    = Array(valid_ids)
        end

        def to_h
          { requested_id: @requested_id, valid_ids: @valid_ids }
        end
      end
    end
  end
end
