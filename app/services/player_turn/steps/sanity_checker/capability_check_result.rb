# frozen_string_literal: true

module PlayerTurn
  module Steps
    module SanityChecker
      class CapabilityCheckResult
        attr_reader :allowed, :reason

        def initialize(allowed:, reason:)
          @allowed = allowed == true
          @reason = reason
        end

        def to_h
          { allowed: allowed, reason: reason }
        end
      end
    end
  end
end
