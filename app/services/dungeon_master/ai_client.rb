# frozen_string_literal: true

module DungeonMaster
  # Thin wrapper around the OpenAI API.
  # Handles request construction, retries for degenerate responses,
  # JSON parsing with fallbacks, and HTTP-level error mapping.
  class AiClient
    MODEL = "gpt-4o-mini".freeze
    MAX_RETRIES = 1

    attr_reader :last_failed_raw_response, :last_parse_status

    def initialize(config)
      @client = OpenAI::Client.new
      @config = config
      @last_failed_raw_response = nil
      @last_parse_status = nil
    end

    # Send a chat completion request and return the raw content string.
    #
    # @param system_prompt [String]
    # @param user_message  [String, nil]  single user message (convenience)
    # @param messages       [Array, nil]   full message list (takes precedence)
    # @param max_tokens     [Integer]
    # @return [String] raw content from the AI
    # @raise [DungeonMasterService::AiError]
    def chat(system_prompt:, user_message: nil, messages: nil, max_tokens: 500)
      chat_messages = [{ role: "system", content: system_prompt }]

      if messages
        chat_messages.concat(messages)
      elsif user_message
        chat_messages << { role: "user", content: user_message }
      end

      params = {
        model: MODEL,
        messages: chat_messages,
        max_tokens: max_tokens,
        temperature: @config.temperature,
        response_format: { type: "json_object" }
      }

      attempt = 0
      loop do
        response = @client.chat(parameters: params)

        if response.dig("error")
          raise DungeonMasterService::AiError,
                response.dig("error", "message") || "OpenAI API error"
        end

        content       = response.dig("choices", 0, "message", "content")
        finish_reason = response.dig("choices", 0, "finish_reason")

        # Detect degenerate whitespace-only responses
        if content.nil? || content.strip.empty?
          attempt += 1
          raw_preview = content&.first(200)&.inspect || "nil"
          Rails.logger.warn(
            "[DungeonMaster::AiClient] Empty/whitespace response (attempt #{attempt}). " \
            "finish_reason=#{finish_reason}, raw preview=#{raw_preview}"
          )

          if attempt <= MAX_RETRIES
            Rails.logger.info("[DungeonMaster::AiClient] Retrying with lower temperature...")
            params[:temperature] = 0.4
            next
          end

          @last_failed_raw_response = content
          raise DungeonMasterService::AiError,
                "Empty response from AI after #{attempt} attempts (finish_reason: #{finish_reason || 'unknown'})"
        end

        if finish_reason == "length"
          Rails.logger.warn(
            "[DungeonMaster::AiClient] Response truncated (finish_reason: length). " \
            "Content length: #{content.length}. Proceeding with partial content."
          )
        end

        return content
      end
    rescue Faraday::TooManyRequestsError
      raise DungeonMasterService::AiError,
            "Rate limited by OpenAI — please wait a moment and try again"
    rescue Faraday::Error => e
      Rails.logger.error("[DungeonMaster::AiClient] Faraday error: #{e.class} - #{e.message}")
      raise DungeonMasterService::AiError,
            "Could not reach the AI service. Please try again shortly."
    end

    # Parse a raw JSON string from the AI, with fallback strategies
    # for when the model returns plain text instead of JSON.
    #
    # @param raw         [String]
    # @param fallback_as [Symbol, nil]  :dm_response or :sanitization
    # @return [Hash]
    # @raise [DungeonMasterService::AiError]
    def parse_json(raw, fallback_as: nil)
      @last_parse_status = "success"

      cleaned = raw.strip
        .gsub(/\A```(?:json)?\s*/, "")
        .gsub(/\s*```\z/, "")
        .strip

      JSON.parse(cleaned)
    rescue JSON::ParserError
      Rails.logger.warn(
        "[DungeonMaster::AiClient] JSON parse failed, attempting fallback. " \
        "Raw (first 500 chars): #{raw&.first(500)}"
      )

      if fallback_as == :dm_response && cleaned.present?
        Rails.logger.info("[DungeonMaster::AiClient] Falling back: treating raw response as narrative text")
        @last_parse_status = "parse_fallback"
        { "narrative" => cleaned, "advance_stage" => false, "roll_request" => nil }
      elsif fallback_as == :sanitization && cleaned.present?
        Rails.logger.info("[DungeonMaster::AiClient] Falling back: treating sanitization as pass-through")
        @last_parse_status = "parse_fallback"
        { "danger_score" => 0, "sanitized_input" => nil, "reason" => nil }
      else
        @last_parse_status = "parse_error"
        raise DungeonMasterService::AiError, "Failed to parse AI response"
      end
    end
  end
end
