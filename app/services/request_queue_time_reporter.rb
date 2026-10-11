# frozen_string_literal: true

class RequestQueueTimeReporter
  REPORT_AFTER_MS = ENV.fetch("REQUEST_QUEUE_REPORT_AFTER_MS", "250").to_i

  def self.call(event)
    measurement = event.payload.fetch(:measurement)
    return unless slow_or_shed?(measurement)

    Rails.logger.warn("[request_queue_time shed] #{measurement.to_h}") if measurement.shed?
    ShipRequestQueueTimeJob.perform_later(measurement.to_h)
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "request_queue_time_reporter" })
  end

  def self.slow_or_shed?(measurement)
    measurement.shed? || measurement.queue_time_ms >= REPORT_AFTER_MS
  end
end
