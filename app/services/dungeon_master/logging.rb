# frozen_string_literal: true

module DungeonMaster
  # Encapsulates all DM-related logging: debug DmLogs and raw AiLogs.
  # Every write is rescue'd so a logging failure never breaks gameplay.
  class Logging
    attr_accessor :player_message_id

    def initialize(adventure:, user:, dm_service: "standard")
      @adventure = adventure
      @user = user
      @dm_service = dm_service
      @player_message_id = nil
    end

    # Write a human-readable debug entry (visible in Admin -> DM Logs).
    def dm_log!(content)
      DmLog.create!(
        adventure: @adventure,
        user: @user,
        content: content
      )
    rescue => e
      Rails.logger.error("[DungeonMaster::Logging] Failed to write DmLog: #{e.message}")
    end

    # Write a full AI exchange record (visible in Admin -> AI Logs).
    def ai_log!(call_type, prompt_summary, raw_response, parsed_response, parse_status:, request_body: nil, model_used: nil)
      AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: prompt_summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: parsed_response&.to_json,
        status: parse_status,
        error_message: nil,
        dm_service: @dm_service,
        model_used: model_used,
        player_message_id: @player_message_id
      )
    rescue => e
      Rails.logger.error("[DungeonMaster::Logging] Failed to write AiLog: #{e.message}")
    end

    # Write an AI error record when a call fails.
    def ai_log_error!(call_type, prompt_summary, error, raw_response: nil, request_body: nil, status: "api_error", model_used: nil)
      AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: prompt_summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: nil,
        status: status,
        error_message: error.message,
        dm_service: @dm_service,
        model_used: model_used,
        player_message_id: @player_message_id
      )
    rescue => e
      Rails.logger.error("[DungeonMaster::Logging] Failed to write AiLog (error): #{e.message}")
    end

    def truncate(text, length: 200)
      text.length > length ? "#{text.first(length)}…" : text
    end
  end
end
