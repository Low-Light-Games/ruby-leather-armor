# frozen_string_literal: true

# Asynchronously ships a PipelineRegistryEntry lifecycle event to Axiom.
# Enqueued by Ai::Logging after each status transition.
#
# Errors are not rescued: Sidekiq retries on failure and sentry-rails captures
# persistent failures via its Sidekiq error handler.
class ShipPipelineRegistryEntryEventJob < ApplicationJob
  queue_as :logging

  def perform(registry_entry_uuid)
    return unless ENV["AXIOM_API_KEY"].present?

    entry = PipelineRegistryEntry.find_by(registry_entry_uuid: registry_entry_uuid)
    return unless entry

    AxiomShipper.ingest(
      _time:                entry.updated_at.utc.iso8601(3),
      registry_entry_uuid:  entry.registry_entry_uuid,
      adventure_id:         entry.adventure_id,
      status:               entry.status,
      active_duration_ms:   entry.active_duration_ms,
      started_at:           entry.started_at&.utc&.iso8601(3),
      finished_at:          entry.finished_at&.utc&.iso8601(3),
      app_version:          entry.app_version,
      event_kind:           "pipeline_registry_entry"
    )
  end
end
