# frozen_string_literal: true

require_relative "request_queue_time/request_start_header"
require_relative "request_queue_time/measurement"

# Measures how long a request waited for a Puma thread, and sheds it with a 503
# once the client has most likely given up.
class RequestQueueTime
  EVENT = "dm.request_queue_time"
  SERVER_TIMING_HEADER = "server-timing"
  PUMA_BODY_WAIT_KEY = "puma.request_body_wait"
  REQUEST_ID_KEY = "action_dispatch.request_id"
  SHED_ERROR_CODE = "request_queue_timeout"

  def initialize(app, shed_after_ms:, retry_after_seconds: 5, exempt_paths: [])
    @app = app
    @shed_after_ms = shed_after_ms.to_i
    @retry_after_seconds = retry_after_seconds.to_i
    @exempt_paths = exempt_paths.to_set.freeze
  end

  def call(env)
    request_start = RequestStartHeader.from_env(env)
    return @app.call(env) unless request_start.present?

    measurement = measure(env, request_start)
    ActiveSupport::Notifications.instrument(EVENT, measurement: measurement)

    response = measurement.shed? ? shed_response : @app.call(env)
    header_enriched_response(response, measurement)
  end

  private

  # Only the headers change; the body passes through so streams keep streaming.
  def header_enriched_response((status, headers, body), measurement)
    queue_timing = "queue;dur=#{measurement.queue_time_ms}"
    headers[SERVER_TIMING_HEADER] = [headers[SERVER_TIMING_HEADER], queue_timing].compact.join(", ")
    [status, headers, body]
  end

  def measure(env, request_start)
    now = Time.now
    queue_time_ms = queue_time_ms(env, request_start, now)

    Measurement.new(
      queue_time_ms: queue_time_ms,
      shed_after_ms: @shed_after_ms,
      shed: shed?(env, queue_time_ms),
      request_id: env[REQUEST_ID_KEY],
      request_method: env["REQUEST_METHOD"],
      path: env["PATH_INFO"],
      measured_at: now
    )
  end

  def queue_time_ms(env, request_start, now)
    waited_ms = ((now.to_f - request_start.started_at) * 1000) - slow_client_upload_ms(env)
    waited_ms.clamp(0.0, nil).round(1)
  end

  def slow_client_upload_ms(env)
    env[PUMA_BODY_WAIT_KEY].to_f
  end

  def shed?(env, queue_time_ms)
    return false unless @shed_after_ms.positive?

    return false if @exempt_paths.include?(env["PATH_INFO"])

    queue_time_ms > @shed_after_ms
  end

  # Same JSON shape as Rack::Attack's throttled response.
  def shed_response
    body = { error: "The server is busy. Please try again in a moment.", error_code: SHED_ERROR_CODE }.to_json
    headers = Rack::Headers.new
    headers["content-type"] = "application/json"
    headers["retry-after"] = @retry_after_seconds.to_s
    [503, headers, [body]]
  end
end
