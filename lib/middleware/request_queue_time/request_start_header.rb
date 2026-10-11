# frozen_string_literal: true

class RequestQueueTime
  # Proxies stamp X-Request-Start in seconds, ms, µs or ns; the magnitude tells which.
  class RequestStartHeader
    RACK_ENV_KEY = "HTTP_X_REQUEST_START"
    UNIT_DIVISORS_BY_MAGNITUDE = [
      [1e17, 1e9], # nanoseconds
      [1e14, 1e6], # microseconds
      [1e11, 1e3], # milliseconds
      [0, 1]       # seconds
    ].freeze
    NUMERIC_TIMESTAMP = /\A\s*(?:t=)?(\d+(?:\.\d+)?)\s*\z/

    def self.from_env(env)
      new(env[RACK_ENV_KEY])
    end

    def initialize(raw_value)
      @raw_value = raw_value.to_s
    end

    def present?
      !started_at.nil?
    end

    def started_at
      return @started_at if defined?(@started_at)

      @started_at = parse
    end

    private

    def parse
      match = NUMERIC_TIMESTAMP.match(@raw_value)
      return unless match

      value = match[1].to_f
      return unless value.positive?

      _, divisor = UNIT_DIVISORS_BY_MAGNITUDE.find { |magnitude, _| value >= magnitude }
      value / divisor
    end
  end
end
