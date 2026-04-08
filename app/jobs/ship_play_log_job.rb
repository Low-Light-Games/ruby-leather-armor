# frozen_string_literal: true

# Asynchronously ships a PlayLog record to Axiom.
#
# Large blob fields (request_body, raw_response, parsed_response) are uploaded
# to S3 first; only the resulting URLs are included in the Axiom event, keeping
# ingestion volume lean.
#
# Enqueued by DungeonMaster::Logging after both PlayLog.create! AND
# attach_usage_record! have returned — ensuring AiUsageRecord is already
# persisted before this job reads the record.
#
# Errors are not rescued: Sidekiq retries on failure and sentry-rails captures
# persistent failures via its Sidekiq error handler.
class ShipPlayLogJob < ApplicationJob
  queue_as :logging

  BLOB_FIELDS = %w[request_body raw_response parsed_response].freeze

  def perform(play_log_id)
    return unless ENV["AXIOM_API_KEY"].present?

    log = PlayLog.includes(:ai_usage_record).find(play_log_id)

    s3_urls = upload_blobs(log)

    AxiomShipper.ingest(build_event(log, s3_urls))
  end

  private

  def upload_blobs(log)
    return {} unless ENV["AWS_S3_ACCESS_KEY_ID"].present?

    BLOB_FIELDS.each_with_object({}) do |field, urls|
      value = log.public_send(field)
      next if value.blank?

      urls[:"s3_#{field}_url"] = S3PayloadStore.upload(
        play_log_id: log.id,
        field_name:  field,
        body:        value
      )
    end
  end

  def build_event(log, s3_urls)
    event = {
      _time:                  log.created_at.utc.iso8601(3),
      play_log_id:            log.id,
      registry_entry_uuid:    log.registry_entry_uuid,
      adventure_id:           log.adventure_id,
      player_message_id:      log.player_message_id,
      player_message_content: log.player_message_content,
      event_type:             log.event_type,
      status:                 log.status,
      dm_service:             log.dm_service,
      model_used:             log.model_used,
      duration_ms:            log.duration_ms,
      prompt_summary:         log.prompt_summary,
      error_message:          log.error_message,
      app_version:            log.app_version
    }.merge(s3_urls)

    if (usage = log.ai_usage_record)
      event.merge!(
        input_tokens:              usage.input_tokens,
        output_tokens:             usage.output_tokens,
        reasoning_tokens:          usage.reasoning_tokens,
        total_tokens:              usage.total_tokens,
        input_cost_microdollars:   usage.input_cost_microdollars,
        output_cost_microdollars:  usage.output_cost_microdollars,
        total_cost_microdollars:   usage.total_cost_microdollars
      )
    end

    event
  end
end
