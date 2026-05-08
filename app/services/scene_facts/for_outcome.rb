# frozen_string_literal: true

module SceneFacts
  class ForOutcome
    def self.call(adventure:, what_happened:, ai:, log:, limit: nil)
      new(adventure: adventure, what_happened: what_happened,
          ai: ai, log: log, limit: limit).call
    end

    def initialize(adventure:, what_happened:, ai:, log:, limit: nil)
      @adventure     = adventure
      @what_happened = what_happened.to_s
      @ai            = ai
      @log           = log
      @limit         = limit
    end

    def call
      Lore::FactsLookup.call(
        adventure:  @adventure,
        ai:         @ai,
        log:        @log,
        query_text: @what_happened,
        limit:      @limit,
      )
    end
  end
end
