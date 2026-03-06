# frozen_string_literal: true

module DungeonMaster
  # Encapsulates all DM-related logging: debug DmLogs and raw AiLogs.
  # Every write is rescue'd so a logging failure never breaks gameplay.
  class Logging
    attr_accessor :player_message_id, :pipeline_run_id, :player_message_content, :action_label

    def initialize(adventure:, user:, dm_service: "standard")
      @adventure = adventure
      @user = user
      @dm_service = dm_service
      @player_message_id = nil
      @pipeline_run_id = nil
      @player_message_content = nil
    end

    def start_pipeline_run!(message_content)
      @pipeline_run_id = SecureRandom.uuid
      @player_message_content = message_content&.truncate(500)
      PipelineRun.create!(
        pipeline_run_id: @pipeline_run_id,
        adventure: @adventure,
        player_message_id: @player_message_id,
        status: "running",
        started_at: Time.current
      )
    rescue => e
      report_error(e, context: { method: "start_pipeline_run!" })
    end

    def resume_pipeline_run!(existing_run_id, message_content)
      @pipeline_run_id = existing_run_id
      @player_message_content = message_content&.truncate(500)
      pipeline_run_record&.update!(status: "running")
    rescue => e
      report_error(e, context: { method: "resume_pipeline_run!" })
    end

    def finish_pipeline_segment!(duration_ms)
      pr = pipeline_run_record
      return unless pr
      pr.update!(active_duration_ms: pr.active_duration_ms + duration_ms)
    rescue => e
      report_error(e, context: { method: "finish_pipeline_segment!" })
    end

    def pause_pipeline_run!
      pipeline_run_record&.update!(status: "paused")
    rescue => e
      report_error(e, context: { method: "pause_pipeline_run!" })
    end

    def complete_pipeline_run!
      pipeline_run_record&.update!(status: "completed", finished_at: Time.current)
    rescue => e
      report_error(e, context: { method: "complete_pipeline_run!" })
    end

    def error_pipeline_run!
      pipeline_run_record&.update!(status: "errored", finished_at: Time.current)
    rescue => e
      report_error(e, context: { method: "error_pipeline_run!" })
    end

    # Write a human-readable debug entry (visible in Admin -> DM Logs).
    def dm_log!(content)
      DmLog.create!(
        adventure: @adventure,
        user: @user,
        content: content
      )
    rescue => e
      report_error(e, context: { method: "dm_log!", content: content&.truncate(200) })
    end

    # Write a full AI exchange record (visible in Admin -> AI Logs).
    def ai_log!(call_type, prompt_summary, raw_response, parsed_response, parse_status:, request_body: nil, model_used: nil, duration_ms: nil, usage: nil)
      summary = @action_label ? "#{@action_label} #{prompt_summary}" : prompt_summary
      log = AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: parsed_response&.to_json,
        status: parse_status,
        error_message: nil,
        dm_service: @dm_service,
        model_used: model_used,
        player_message_id: @player_message_id,
        pipeline_run_id: @pipeline_run_id,
        player_message_content: @player_message_content,
        duration_ms: duration_ms
      )
      attach_usage_record!(log, model_used, usage)
    rescue => e
      report_error(e, context: { method: "ai_log!", call_type: call_type })
      try_fallback_log(call_type, e)
    end

    # Write an AI error record when a call fails.
    def ai_log_error!(call_type, prompt_summary, error, raw_response: nil, request_body: nil, status: "api_error", model_used: nil, duration_ms: nil, usage: nil)
      summary = @action_label ? "#{@action_label} #{prompt_summary}" : prompt_summary
      log = AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: nil,
        status: status,
        error_message: error.message,
        dm_service: @dm_service,
        model_used: model_used,
        player_message_id: @player_message_id,
        pipeline_run_id: @pipeline_run_id,
        player_message_content: @player_message_content,
        duration_ms: duration_ms
      )
      attach_usage_record!(log, model_used, usage)
    rescue => e
      report_error(e, context: { method: "ai_log_error!", call_type: call_type, original_error: error.message })
      try_fallback_log(call_type, e)
    end

    def truncate(text, length: 200)
      text.length > length ? "#{text.first(length)}…" : text
    end

    private

    def attach_usage_record!(ai_log, model_used, usage)
      return unless usage.is_a?(Hash) && model_used.present?

      costs = AiUsageRecord.compute_cost(
        model_used,
        usage[:input_tokens] || 0,
        usage[:output_tokens] || 0,
        usage[:reasoning_tokens] || 0
      )

      record = AiUsageRecord.create!(
        ai_log_id: ai_log.id,
        adventure_id: @adventure&.id,
        user_id: @user&.id,
        pipeline_run_id: @pipeline_run_id,
        model_id: model_used,
        call_type: ai_log.call_type,
        input_tokens: usage[:input_tokens] || 0,
        output_tokens: usage[:output_tokens] || 0,
        reasoning_tokens: usage[:reasoning_tokens] || 0,
        total_tokens: usage[:total_tokens] || 0,
        **costs
      )

      ai_log.update_column(:ai_usage_record_id, record.id)
    rescue => e
      report_error(e, context: { method: "attach_usage_record!", ai_log_id: ai_log&.id })
    end

    def pipeline_run_record
      return nil unless @pipeline_run_id
      PipelineRun.find_by(pipeline_run_id: @pipeline_run_id)
    end

    def report_error(exception, context: {})
      full_context = {
        pipeline_run_id: @pipeline_run_id,
        adventure_id: @adventure&.id,
        player_message_id: @player_message_id
      }.merge(context)

      Rails.error.report(exception, handled: true, context: full_context)
    end

    # Last-resort write when the primary ai_log! or ai_log_error! fails.
    # Uses minimal fields to maximize the chance of passing validation.
    def try_fallback_log(call_type, original_error)
      AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: "LOGGING FAILURE: #{original_error.message.truncate(400)}",
        raw_response: nil,
        parsed_response: nil,
        status: "logging_error",
        error_message: original_error.message,
        dm_service: @dm_service,
        player_message_id: @player_message_id,
        pipeline_run_id: @pipeline_run_id,
        player_message_content: @player_message_content
      )
    rescue => inner
      report_error(inner, context: { method: "try_fallback_log", call_type: call_type, original_error: original_error.message })
    end
  end
end
