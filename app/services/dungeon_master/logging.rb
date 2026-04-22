# frozen_string_literal: true

module DungeonMaster
  # Encapsulates all DM-related logging: PlayLogs (AI calls and pipeline events)
  # and structured Rails.logger output for errors.
  # Every write is rescue'd so a logging failure never breaks gameplay.
  class Logging
    attr_accessor :player_message_id, :registry_entry_uuid, :player_message_content, :action_label

    def initialize(adventure:, user:, dm_service: "standard")
      @adventure = adventure
      @user = user
      @dm_service = dm_service
      @player_message_id = nil
      @registry_entry_uuid = nil
      @player_message_content = nil
    end

    def start_registry_entry!(message_content)
      @registry_entry_uuid = SecureRandom.uuid
      @player_message_content = message_content&.truncate(500)
      PipelineRegistryEntry.create!(
        registry_entry_uuid: @registry_entry_uuid,
        adventure: @adventure,
        player_message_id: @player_message_id,
        status: "running",
        started_at: Time.current,
        app_version: APP_VERSION
      )
      enqueue_registry_entry_event!
    rescue => e
      report_error(e, context: { method: "start_registry_entry!" })
    end

    def resume_registry_entry!(existing_uuid, message_content)
      @registry_entry_uuid = existing_uuid
      @player_message_content = message_content&.truncate(500)
      registry_entry_record&.update!(status: "running")
    rescue => e
      report_error(e, context: { method: "resume_registry_entry!" })
    end

    def finish_pipeline_segment!(duration_ms)
      pr = registry_entry_record
      return unless pr

      pr.update!(active_duration_ms: pr.active_duration_ms + duration_ms)
    rescue => e
      report_error(e, context: { method: "finish_pipeline_segment!" })
    end

    def pause_registry_entry!
      registry_entry_record&.update!(status: "paused")
      enqueue_registry_entry_event!
    rescue => e
      report_error(e, context: { method: "pause_registry_entry!" })
    end

    def complete_registry_entry!
      registry_entry_record&.update!(status: "completed", finished_at: Time.current)
      enqueue_registry_entry_event!
    rescue => e
      report_error(e, context: { method: "complete_registry_entry!" })
    end

    def error_registry_entry!(exception = nil)
      registry_entry_record&.update!(status: "errored", finished_at: Time.current)
      enqueue_registry_entry_event!
    rescue => e
      report_error(e, context: { method: "error_registry_entry!" })
    end

    # Write a structured pipeline event (sanity rejections, queue state, etc.)
    # visible in Admin -> Play Logs. No AI columns are populated.
    # Pass parsed_response: a Hash to store structured data shown in the pipeline card body.
    def play_log!(event_type, summary, parsed_response: nil)
      log = PlayLog.create!(
        adventure: @adventure,
        event_type: event_type,
        prompt_summary: summary,
        parsed_response: parsed_response&.to_json,
        status: "pipeline_event",
        dm_service: @dm_service,
        player_message_id: @player_message_id,
        registry_entry_uuid: @registry_entry_uuid,
        player_message_content: @player_message_content,
        app_version: APP_VERSION
      )
      enqueue_play_log_event!(log)
    rescue => e
      report_error(e, context: { method: "play_log!", event_type: event_type })
    end

    # Emit a tagged Rails.logger message for errors and warnings.
    # Vendor SDKs (Sentry, Datadog, etc.) absorb this automatically.
    def log!(level, message)
      Rails.logger.public_send(level,
        "[DM adventure=#{@adventure&.id} registry=#{@registry_entry_uuid}] #{message}")
    end

    # Write a full AI exchange record (visible in Admin -> Play Logs).
    def ai_log!(call_type, prompt_summary, raw_response, parsed_response, parse_status:, request_body: nil, model_used: nil, duration_ms: nil, usage: nil)
      summary = @action_label ? "#{@action_label} #{prompt_summary}" : prompt_summary
      log = PlayLog.create!(
        adventure: @adventure,
        event_type: call_type,
        prompt_summary: summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: parsed_response&.to_json,
        status: parse_status,
        error_message: nil,
        dm_service: @dm_service,
        model_used: model_used,
        player_message_id: @player_message_id,
        registry_entry_uuid: @registry_entry_uuid,
        player_message_content: @player_message_content,
        duration_ms: duration_ms,
        app_version: APP_VERSION
      )
      attach_usage_record!(log, model_used, usage)
      enqueue_play_log_event!(log)
    rescue => e
      report_error(e, context: { method: "ai_log!", call_type: call_type })
      try_fallback_log(call_type, e)
    end

    # Write an AI error record when a call fails.
    def ai_log_error!(call_type, prompt_summary, error, raw_response: nil, request_body: nil, status: "api_error", model_used: nil, duration_ms: nil, usage: nil)
      summary = @action_label ? "#{@action_label} #{prompt_summary}" : prompt_summary
      log = PlayLog.create!(
        adventure: @adventure,
        event_type: call_type,
        prompt_summary: summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: nil,
        status: status,
        error_message: error.message,
        dm_service: @dm_service,
        model_used: model_used,
        player_message_id: @player_message_id,
        registry_entry_uuid: @registry_entry_uuid,
        player_message_content: @player_message_content,
        duration_ms: duration_ms,
        app_version: APP_VERSION
      )
      attach_usage_record!(log, model_used, usage)
      enqueue_play_log_event!(log)
    rescue => e
      report_error(e, context: { method: "ai_log_error!", call_type: call_type, original_error: error.message })
      try_fallback_log(call_type, e)
    end

    def truncate(text, length: 200)
      text.length > length ? "#{text.first(length)}…" : text
    end

    # Sentry + Rails.error for pipeline exceptions surfaced to the player — never raises.
    def capture_pipeline_exception!(exception)
      Rails.logger.error(
        "[DM pipeline exception adventure=#{@adventure&.id} registry=#{@registry_entry_uuid}] " \
        "#{exception.class}: #{exception.message}\n#{Array(exception.backtrace).join("\n")}"
      )
      play_log!(
        "pipeline_error",
        "#{exception.class}: #{exception.message}",
        parsed_response: {
          error_class: exception.class.name,
          error_message: exception.message,
          backtrace: Array(exception.backtrace).first(25)
        }
      )
      ApplicationErrorReporter.notify(exception, context: {
        source: "dungeon_master_pipeline_exception",
        registry_entry_uuid: @registry_entry_uuid,
        adventure_id: @adventure&.id,
        player_message_id: @player_message_id
      })
    end

    # When the player starts a new prompt while a roll/initiative request is still pending.
    # Sentry + context-merged error notification. Public so best-effort
    # services like `Lore::ApplyResults` (Loremaster apply path) can
    # observe their lossy failures without losing the structured
    # registry/adventure/user context. Internal callers below `private`
    # still invoke the same method directly.
    def report_error(exception, context: {})
      full_context = {
        registry_entry_uuid: @registry_entry_uuid,
        adventure_id: @adventure&.id,
        player_message_id: @player_message_id
      }.merge(context)

      ApplicationErrorReporter.notify(exception, context: full_context)
    end

    def log_abandoned_pipeline_if_needed!
      msgs = @adventure.adventure_messages
      last_request = msgs.for_message_types(%w[roll_request initiative_request]).newest_first.first
      return unless last_request&.metadata&.dig("intent")

      last_player_msg = msgs.from_players.newest_first.first
      return if last_player_msg&.message_type.in?(%w[roll_result initiative_result])

      intent_summary = last_request.metadata.dig("intent", "intention").to_s.truncate(80)
      play_log!(
        "pipeline_abandoned",
        "Previous pipeline abandoned (#{last_request.message_type}): player sent new input. " \
        "Original intent: #{intent_summary}"
      )
    end

    private

    def attach_usage_record!(play_log, model_used, usage)
      return unless usage.is_a?(Hash) && model_used.present?

      costs = AiUsageRecord.compute_cost(
        model_used,
        usage[:input_tokens] || 0,
        usage[:output_tokens] || 0,
        usage[:reasoning_tokens] || 0
      )

      record = AiUsageRecord.create!(
        ai_log_id: play_log.id,
        adventure_id: @adventure&.id,
        user_id: @user&.id,
        registry_entry_uuid: @registry_entry_uuid,
        model_id: model_used,
        event_type: play_log.event_type,
        input_tokens: usage[:input_tokens] || 0,
        output_tokens: usage[:output_tokens] || 0,
        reasoning_tokens: usage[:reasoning_tokens] || 0,
        total_tokens: usage[:total_tokens] || 0,
        **costs
      )

      play_log.update_column(:ai_usage_record_id, record.id)
    rescue => e
      report_error(e, context: { method: "attach_usage_record!", play_log_id: play_log&.id })
    end

    def registry_entry_record
      return nil unless @registry_entry_uuid

      PipelineRegistryEntry.find_by(registry_entry_uuid: @registry_entry_uuid)
    end

    def enqueue_play_log_event!(log)
      ShipPlayLogJob.perform_later(log.id)
    rescue => e
      report_error(e, context: { method: "enqueue_play_log_event!", play_log_id: log&.id })
    end

    def enqueue_registry_entry_event!
      return unless @registry_entry_uuid

      ShipPipelineRegistryEntryEventJob.perform_later(@registry_entry_uuid)
    rescue => e
      report_error(e, context: { method: "enqueue_registry_entry_event!", registry_entry_uuid: @registry_entry_uuid })
    end

    # Last-resort write when the primary ai_log! or ai_log_error! fails.
    # Uses minimal fields to maximize the chance of passing validation.
    def try_fallback_log(call_type, original_error)
      PlayLog.create!(
        adventure: @adventure,
        event_type: call_type,
        prompt_summary: "LOGGING FAILURE: #{original_error.message.truncate(400)}",
        raw_response: nil,
        parsed_response: nil,
        status: "logging_error",
        error_message: original_error.message,
        dm_service: @dm_service,
        player_message_id: @player_message_id,
        registry_entry_uuid: @registry_entry_uuid,
        player_message_content: @player_message_content
      )
    rescue => inner
      report_error(inner, context: { method: "try_fallback_log", call_type: call_type, original_error: original_error.message })
    end
  end
end
