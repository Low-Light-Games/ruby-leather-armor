# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      class MechEvalOwnershipViolationLogPayload
        def initialize(domain:, violation:, roll:)
          @domain = domain
          @violation = violation
          @roll = roll
        end

        def to_h
          {
            domain: @domain,
            violation: @violation,
            roll: @roll
          }
        end
      end
    end
  end
end
