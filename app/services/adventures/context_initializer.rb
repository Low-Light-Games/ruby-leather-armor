# frozen_string_literal: true

module Adventures
  # Builds the initial traversal and time contexts when starting a new adventure.
  class ContextInitializer
    TIME_CUE_PATTERNS = {
      /\b(\d{1,2})\s*(?:in the\s+)?(?:am|a\.m\.|in the morning)\b/i => ->(m) { m[1].to_i },
      /\b(\d{1,2})\s*(?:pm|p\.m\.|in the (?:afternoon|evening))\b/i => ->(m) { m[1].to_i + 12 },
      /\bmidnight\b/i      => ->(_) { 0 },
      /\bnoon\b/i          => ->(_) { 12 },
      /\bmidday\b/i        => ->(_) { 12 },
      /\bdawn\b/i          => ->(_) { 6 },
      /\bsunrise\b/i       => ->(_) { 6 },
      /\bdusk\b/i          => ->(_) { 19 },
      /\bsunset\b/i        => ->(_) { 19 },
      /\bmorning\b/i       => ->(_) { 8 },
      /\bafternoon\b/i     => ->(_) { 14 },
      /\bevening\b/i       => ->(_) { 19 },
      /\bnight\b/i         => ->(_) { 21 },
    }.freeze

    def initialize(story)
      @story = story
    end

    def build_time_context
      seeded_time = @story.initial_contexts&.dig("traversal_context", "time_of_day")
      Adventures::TimeContext.new(hour: parse_time_cue(seeded_time) || 8).to_h
    end

    def build_traversal(start_loc)
      Adventures::TraversalContext.new(start_location: start_loc).to_h
    end

    private

    def parse_time_cue(text)
      return nil if text.blank?

      TIME_CUE_PATTERNS.each do |pattern, extractor|
        match = text.match(pattern)
        return extractor.call(match) if match
      end
      nil
    end
  end
end
