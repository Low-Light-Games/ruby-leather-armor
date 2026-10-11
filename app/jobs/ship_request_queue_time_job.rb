# frozen_string_literal: true

# Ships one RequestQueueTime::Measurement (as its #to_h) to Axiom.
# Enqueued by RequestQueueTimeReporter so the HTTP POST never runs on a web thread.
#
# Errors are not rescued: Sidekiq retries on failure and sentry-rails captures
# persistent failures via its Sidekiq error handler.
class ShipRequestQueueTimeJob < ApplicationJob
  queue_as :logging

  def perform(event)
    return unless ENV["AXIOM_API_KEY"].present?

    AxiomShipper.ingest(event)
  end
end
