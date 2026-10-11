# frozen_string_literal: true

class ShipRequestQueueTimeJob < ApplicationJob
  queue_as :logging

  def perform(event)
    return unless ENV["AXIOM_API_KEY"].present?

    AxiomShipper.ingest(event)
  end
end
