# frozen_string_literal: true

# Asynchronously ships a PipelineRun lifecycle event to Axiom.
# Enqueued by DungeonMaster::Logging after each status transition.
#
# Errors are not rescued: Sidekiq retries on failure and sentry-rails captures
# persistent failures via its Sidekiq error handler.
class ShipPipelineRunEventJob < ApplicationJob
  queue_as :logging

  def perform(pipeline_run_id)
    return unless ENV["AXIOM_API_KEY"].present?

    run = PipelineRun.find_by(pipeline_run_id: pipeline_run_id)
    return unless run

    AxiomShipper.ingest(
      _time:              run.updated_at.utc.iso8601(3),
      pipeline_run_id:    run.pipeline_run_id,
      adventure_id:       run.adventure_id,
      status:             run.status,
      active_duration_ms: run.active_duration_ms,
      step_count:         run.step_count,
      started_at:         run.started_at&.utc&.iso8601(3),
      finished_at:        run.finished_at&.utc&.iso8601(3),
      app_version:        run.app_version,
      event_kind:         "pipeline_run"
    )
  end
end
