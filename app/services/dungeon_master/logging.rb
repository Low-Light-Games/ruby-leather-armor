# frozen_string_literal: true

module DungeonMaster
  # Encapsulates all DM-related logging: debug DmLogs and raw AiLogs.
  # Every write is rescue'd so a logging failure never breaks gameplay.
  class Logging
    def initialize(adventure:, user:, dm_service: "standard")
      @adventure = adventure
      @user = user
      @dm_service = dm_service
    end

    # Write a human-readable debug entry (visible in Admin → DM Logs).
    #
    # @param content [String]
    def dm_log!(content)
      DmLog.create!(
        adventure: @adventure,
        user: @user,
        content: content
      )
    rescue => e
      Rails.logger.error("[DungeonMaster::Logging] Failed to write DmLog: #{e.message}")
    end

    # Write a full AI exchange record (visible in Admin → AI Logs).
    #
    # @param call_type       [String]  e.g. "sanitization", "dm_response", "roll_response"
    # @param prompt_summary  [String]  short description of what was sent
    # @param raw_response    [String]  the raw AI output
    # @param parsed_response [Hash]    the parsed result
    # @param parse_status    [String]  "success", "parse_fallback", etc.
    # @param request_body    [Hash, nil]  the system prompt + messages sent to the AI
    def ai_log!(call_type, prompt_summary, raw_response, parsed_response, parse_status:, request_body: nil)
      AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: prompt_summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: parsed_response&.to_json,
        status: parse_status,
        error_message: nil,
        dm_service: @dm_service
      )
    rescue => e
      Rails.logger.error("[DungeonMaster::Logging] Failed to write AiLog: #{e.message}")
    end

    # Write an AI error record when a call fails.
    #
    # @param call_type      [String]
    # @param prompt_summary [String]
    # @param error          [StandardError]
    # @param raw_response   [String, nil]
    # @param request_body   [Hash, nil]
    def ai_log_error!(call_type, prompt_summary, error, raw_response: nil, request_body: nil)
      AiLog.create!(
        adventure: @adventure,
        call_type: call_type,
        prompt_summary: prompt_summary,
        request_body: request_body&.to_json,
        raw_response: raw_response,
        parsed_response: nil,
        status: "api_error",
        error_message: error.message,
        dm_service: @dm_service
      )
    rescue => e
      Rails.logger.error("[DungeonMaster::Logging] Failed to write AiLog (error): #{e.message}")
    end

    # Truncate text for log entries.
    #
    # @param text   [String]
    # @param length [Integer]
    # @return [String]
    def truncate(text, length: 200)
      text.length > length ? "#{text.first(length)}…" : text
    end
  end
end
