# frozen_string_literal: true

module DungeonMaster
  # Thin wrapper around the OpenAI API.
  # Handles request construction, JSON parsing with fallbacks,
  # and HTTP-level error mapping.
  class AiClient
    MAX_RETRIES = 2
    RETRY_BASE_DELAY = 1.0 # seconds; doubles each retry

    attr_reader :last_failed_raw_response, :last_parse_status, :last_model_used, :last_usage

    def initialize(config)
      @client = OpenAI::Client.new
      @config = config
      @default_model = config.model
      @last_failed_raw_response = nil
      @last_parse_status = nil
      @last_model_used = nil
      @last_usage = nil
    end

    # Send a chat completion request and return the raw content string.
    # Retries up to MAX_RETRIES times on transient network errors and rate limits.
    #
    # @param system_prompt [String]
    # @param user_message  [String, nil]  single user message (convenience)
    # @param messages       [Array, nil]   full message list (takes precedence)
    # @param max_tokens     [Integer]      token budget for this step
    # @param step_name      [String, nil]  pipeline step name for error messages
    # @param model          [String, nil]  per-step model override (falls back to default)
    # @return [String] raw content from the AI
    # @raise [DungeonMaster::AiError]
    def chat(system_prompt:, user_message: nil, messages: nil, max_tokens: 500, step_name: nil, model: nil)
      @last_usage = nil
      effective_model = model || @default_model
      @last_model_used = effective_model
      supports_temp = OpenaiModelCatalog.supports_temperature?(effective_model)

      chat_messages = [{ role: "system", content: system_prompt }]

      if messages
        chat_messages.concat(messages)
      elsif user_message
        chat_messages << { role: "user", content: user_message }
      end

      params = {
        model: effective_model,
        messages: chat_messages,
        max_completion_tokens: max_tokens,
        response_format: { type: "json_object" }
      }
      params[:temperature] = @config.temperature if supports_temp && @config.temperature != 1.0

      attempt = 0
      begin
        attempt += 1
        response = @client.chat(parameters: params)
      rescue Faraday::TooManyRequestsError => e
        if attempt <= MAX_RETRIES
          delay = RETRY_BASE_DELAY * (2**(attempt - 1))
          Rails.logger.warn("[DungeonMaster::AiClient] Rate limited (attempt #{attempt}/#{MAX_RETRIES + 1}), retrying in #{delay}s")
          sleep(delay)
          retry
        end
        raise AiError, "Rate limited by OpenAI after #{attempt} attempts"
      rescue Faraday::BadRequestError => e
        body = begin; e.response&.dig(:body); rescue StandardError; nil; end
        msg = body.is_a?(Hash) ? body.dig("error", "message") : e.message
        Rails.logger.error("[DungeonMaster::AiClient] Bad request: #{msg}")
        raise AiError, "AI request rejected: #{msg}"
      rescue Faraday::Error => e
        if attempt <= MAX_RETRIES
          delay = RETRY_BASE_DELAY * (2**(attempt - 1))
          Rails.logger.warn("[DungeonMaster::AiClient] #{e.class} (attempt #{attempt}/#{MAX_RETRIES + 1}), retrying in #{delay}s: #{e.message}")
          sleep(delay)
          retry
        end
        Rails.logger.error("[DungeonMaster::AiClient] #{e.class} after #{attempt} attempts: #{e.message}")
        raise AiError, "Could not reach the AI service after #{attempt} attempts. Please try again shortly."
      end

      if response.dig("error")
        raise AiError, response.dig("error", "message") || "OpenAI API error"
      end

      content       = response.dig("choices", 0, "message", "content")
      finish_reason = response.dig("choices", 0, "finish_reason")

      usage_hash = response["usage"]
      if usage_hash
        reasoning = usage_hash.dig("completion_tokens_details", "reasoning_tokens") || 0
        @last_usage = {
          input_tokens: usage_hash["prompt_tokens"] || 0,
          output_tokens: usage_hash["completion_tokens"] || 0,
          reasoning_tokens: reasoning,
          total_tokens: usage_hash["total_tokens"] || 0
        }
      end

      if finish_reason == "length"
        label = step_name || "unknown"
        @last_failed_raw_response = content
        Rails.logger.error(
          "[DungeonMaster::AiClient] Token budget exceeded on '#{label}' step " \
          "(budget: #{max_tokens}, finish_reason: length, content_length: #{content&.length || 0})"
        )
        raise TokenBudgetExceededError.new(step_name: label, budget: max_tokens)
      end

      if content.nil? || content.strip.empty?
        @last_failed_raw_response = content
        raise AiError, "Empty response from AI (finish_reason: #{finish_reason || 'unknown'})"
      end

      content
    end

    # Parse a raw JSON string from the AI, with fallback strategies
    # for when the model returns plain text instead of JSON.
    #
    # @param raw         [String]
    # @param fallback_as [Symbol, nil]  :dm_response to treat raw text as narrative on parse failure
    # @return [Hash]
    # @raise [DungeonMaster::AiError]
    def parse_json(raw, fallback_as: nil)
      @last_parse_status = "success"

      cleaned = raw.strip
        .gsub(/\A```(?:json)?\s*/, "")
        .gsub(/\s*```\z/, "")
        .strip

      JSON.parse(cleaned)
    rescue JSON::ParserError
      Rails.logger.warn(
        "[DungeonMaster::AiClient] JSON parse failed. " \
        "Raw (first 500 chars): #{raw&.first(500)}"
      )

      # The Narrate step produces prose that may not be valid JSON.
      # Treating raw text as narrative is a valid degradation — the
      # content is still usable. All other steps must parse or fail.
      if fallback_as == :dm_response && cleaned.present?
        Rails.logger.info("[DungeonMaster::AiClient] Falling back: treating raw response as narrative text")
        @last_parse_status = "parse_fallback"
        { "narrative" => cleaned }
      else
        @last_parse_status = "parse_error"
        raise AiError, "Failed to parse AI response as JSON"
      end
    end
  end
end
