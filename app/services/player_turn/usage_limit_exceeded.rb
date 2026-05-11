# frozen_string_literal: true

module PlayerTurn
  class UsageLimitExceeded < StandardError
    def initialize(msg = nil)
      super(msg || "You've reached your monthly usage limit. Your budget resets at the start of next month.")
    end
  end
end
