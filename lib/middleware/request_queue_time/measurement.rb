# frozen_string_literal: true

class RequestQueueTime
  # Payload of the `RequestQueueTime::EVENT` notification: one per request that
  # arrived with an `X-Request-Start` stamp.
  class Measurement
    attr_reader :queue_time_ms, :shed_after_ms, :request_id, :request_method, :path, :measured_at

    def initialize(queue_time_ms:, shed_after_ms:, shed:, request_id:, request_method:, path:, measured_at:)
      @queue_time_ms  = queue_time_ms
      @shed_after_ms  = shed_after_ms
      @shed           = shed
      @request_id     = request_id
      @request_method = request_method
      @path           = path
      @measured_at    = measured_at
    end

    def shed?
      @shed
    end

    def to_h
      {
        _time:          @measured_at.utc.iso8601(3),
        event_kind:     "request_queue_time",
        queue_time_ms:  @queue_time_ms,
        shed_after_ms:  @shed_after_ms,
        shed:           @shed,
        request_id:     @request_id,
        request_method: @request_method,
        path:           @path
      }
    end
  end
end
