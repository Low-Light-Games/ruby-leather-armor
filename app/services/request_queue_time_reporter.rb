# frozen_string_literal: true

# Subscriber for RequestQueueTime::EVENT. Every proxied request instruments, so
# only the slow tail and shed requests are shipped to Axiom; the healthy rest
# stays visible per request through the `Server-Timing: queue` header.
class RequestQueueTimeReporter
  REPORT_AFTER_MS = ENV.fetch("REQUEST_QUEUE_REPORT_AFTER_MS", "250").to_i

  def self.call(event)
    measurement = event.payload.fetch(:measurement)
    return unless reportable?(measurement)

    Rails.logger.warn("[request_queue_time shed] #{measurement.to_h}") if measurement.shed?
    ShipRequestQueueTimeJob.perform_later(measurement.to_h)
  rescue StandardError => e
    # Runs inline on the web thread, so telemetry must never fail the request.
    ApplicationErrorReporter.notify(e, context: { source: "request_queue_time_reporter" })
  end

  def self.reportable?(measurement)
    measurement.shed? || measurement.queue_time_ms >= REPORT_AFTER_MS
  end
end
