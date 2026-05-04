# frozen_string_literal: true

require 'bigdecimal'

module DungeonMaster
  # Thin wrapper around the OpenAI API.
  # Handles request construction, JSON parsing with fallbacks,
  # and HTTP-level error mapping.
  class AiClient
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_RETRY_BASE_DELAY_SECONDS = 0.5
    DEFAULT_RETRY_MAX_DELAY_SECONDS = 8.0

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
    # Retries up to the configured retry budget on transient network errors and rate limits.
    #
    # @param system_prompt [String]
    # @param user_message  [String, nil]  single user message (convenience)
    # @param messages       [Array, nil]   full message list (takes precedence)
    # @param step_name        [String, nil]  pipeline step name for error messages
    # @param model            [String, nil]  per-step model override (falls back to default)
    # @param reasoning_effort [String, nil]  one of "minimal" | "low" | "medium" | "high".
    #                                        Only sent when the model is a reasoning model
    #                                        (per OpenaiModelCatalog#reasoning_model?). Non-reasoning
    #                                        models would 400 if we passed it.
    # @return [String] raw content from the AI
    # @raise [DungeonMaster::AiError]
    def chat(system_prompt:, user_message: nil, messages: nil, step_name: nil, model: nil, reasoning_effort: nil)
      @last_usage = nil
      effective_model = model || @default_model
      @last_model_used = effective_model
      supports_temp = OpenaiModelCatalog.supports_temperature?(effective_model)
      is_reasoning  = OpenaiModelCatalog.reasoning_model?(effective_model)

      chat_messages = [{ role: "system", content: system_prompt }]

      if messages
        chat_messages.concat(messages)
      elsif user_message
        chat_messages << { role: "user", content: user_message }
      end

      params = {
        model: effective_model,
        messages: chat_messages,
        response_format: { type: "json_object" }
      }
      params[:temperature] = @config.temperature if supports_temp && custom_temperature?
      params[:reasoning_effort] = reasoning_effort if reasoning_effort.present? && is_reasoning

      response = begin
        with_openai_retries(call_type: "chat", model: effective_model) do
          @client.chat(parameters: params)
        end
      rescue Faraday::BadRequestError => e
        body = begin; e.response&.dig(:body); rescue StandardError; nil; end
        msg = body.is_a?(Hash) ? body.dig("error", "message") : e.message
        Rails.logger.error("[DungeonMaster::AiClient] Bad request: #{msg}")
        raise AiError, "AI request rejected: #{msg}"
      rescue Faraday::TooManyRequestsError => e
        Rails.logger.error("[DungeonMaster::AiClient] Rate limited after #{openai_max_retries + 1} attempts: #{e.message}")
        raise AiError, "Rate limited by OpenAI after #{openai_max_retries + 1} attempts"
      rescue Faraday::ClientError => e
        Rails.logger.error("[DungeonMaster::AiClient] #{e.class}: #{e.message}")
        raise AiError, "AI request rejected: #{e.message}"
      rescue Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
        Rails.logger.error("[DungeonMaster::AiClient] #{e.class} after #{openai_max_retries + 1} attempts: #{e.message}")
        raise AiError, "Could not reach the AI service after #{openai_max_retries + 1} attempts. Please try again shortly."
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
          "[DungeonMaster::AiClient] Token limit hit on '#{label}' step " \
          "(finish_reason: length, content_length: #{content&.length || 0})"
        )
        raise TokenBudgetExceededError.new(step_name: label, budget: nil)
      end

      if content.nil? || content.strip.empty?
        @last_failed_raw_response = content
        raise AiError, "Empty response from AI (finish_reason: #{finish_reason || 'unknown'})"
      end

      content
    end

    # Compute embeddings for an array of texts in a single HTTP round-trip.
    #
    # The OpenAI embeddings endpoint accepts an array `input`, so batching
    # N texts is one HTTP call rather than N — this is what lets the
    # per-turn Loremaster apply stay within the "zero added wall-clock
    # latency" envelope regardless of fact count. Single-text callers pass
    # a 1-element array and use `embeddings(...).first`.
    #
    # Retries follow the same transient-error pattern as `#chat` (rate
    # limits + retryable Faraday failures retried up to the configured retry budget,
    # bad-request errors raised immediately).
    #
    # AiLog writes are intentionally the caller's responsibility — `AiClient`
    # holds HTTP + retry only and does not know about `@adventure` / `@log` /
    # prompt summaries. Call sites wrap this with `DungeonMaster::Logging#ai_log!`
    # / `#ai_log_error!` using `call_type: "embedding"`. See Lore::ApplyResults
    # (write path) and Lore::FactsLookup (read path).
    #
    # @param texts      [Array<String>]  non-empty array of texts to embed
    # @param model      [String]         embedding model id — required; callers
    #                                    read it from DmConfig so the admin UI
    #                                    selection is authoritative and no
    #                                    hardcoded default can drift from it.
    # @param dimensions [Integer, nil]   optional output-dim truncation (only
    #                                    honored by `text-embedding-3-*` models).
    #                                    Pass 1536 when using `-3-large` so its
    #                                    native-3072 output fits our column.
    # @return [Array<Array<Float>>]      parallel array of vectors (dim =
    #                                    `dimensions` if given, else model's
    #                                    native), in the same order as `texts`
    # @raise [DungeonMaster::AiError]
    def embeddings(texts:, model:, dimensions: nil)
      raise AiError, "embeddings called with no texts" if texts.nil? || texts.empty?

      params = { model: model, input: texts }
      params[:dimensions] = dimensions if dimensions

      response = begin
        with_openai_retries(call_type: "embeddings", model: model) do
          @client.embeddings(parameters: params)
        end
      rescue Faraday::BadRequestError => e
        body = begin; e.response&.dig(:body); rescue StandardError; nil; end
        msg = body.is_a?(Hash) ? body.dig("error", "message") : e.message
        Rails.logger.error("[DungeonMaster::AiClient] Embeddings bad request: #{msg}")
        raise AiError, "AI embeddings request rejected: #{msg}"
      rescue Faraday::TooManyRequestsError => e
        Rails.logger.error("[DungeonMaster::AiClient] Embeddings rate limited after #{openai_max_retries + 1} attempts: #{e.message}")
        raise AiError, "Embeddings rate limited by OpenAI after #{openai_max_retries + 1} attempts"
      rescue Faraday::ClientError => e
        Rails.logger.error("[DungeonMaster::AiClient] Embeddings #{e.class}: #{e.message}")
        raise AiError, "AI embeddings request rejected: #{e.message}"
      rescue Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
        Rails.logger.error("[DungeonMaster::AiClient] Embeddings #{e.class} after #{openai_max_retries + 1} attempts: #{e.message}")
        raise AiError, "Could not reach the AI embeddings service after #{openai_max_retries + 1} attempts."
      end

      if response.is_a?(Hash) && response.dig("error")
        raise AiError, response.dig("error", "message") || "OpenAI embeddings API error"
      end

      data = response.is_a?(Hash) ? response["data"] : nil
      unless data.is_a?(Array) && data.length == texts.length
        raise AiError, "Unexpected embeddings response shape (got #{data&.length || 'nil'} vectors for #{texts.length} texts)"
      end

      usage = response["usage"] || {}
      prompt_tokens = usage["prompt_tokens"].to_i
      @last_usage = {
        input_tokens:     prompt_tokens,
        output_tokens:    0,
        reasoning_tokens: 0,
        total_tokens:     prompt_tokens,
      }

      # Sort defensively by `index` — the API is spec'd to return elements
      # in input order, but aligning on `index` makes the contract explicit
      # if an upstream shim ever shuffles them.
      data.sort_by { |row| row["index"].to_i }.map { |row| row["embedding"] }
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

    private

    def with_openai_retries(call_type:, model:)
      attempt = 0

      begin
        attempt += 1
        yield
      rescue Faraday::TooManyRequestsError, Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise unless retry_openai_error?(attempt, e)

        delay, retry_after = retry_delay_for(attempt:, exception: e)
        log_retry(call_type:, model:, attempt:, exception: e, delay:, retry_after:)
        sleep(delay)
        retry
      end
    end

    def retry_openai_error?(attempt, exception)
      return false if attempt > openai_max_retries

      exception.is_a?(Faraday::TooManyRequestsError) ||
        exception.is_a?(Faraday::ServerError) ||
        exception.is_a?(Faraday::ConnectionFailed) ||
        exception.is_a?(Faraday::TimeoutError)
    end

    def retry_delay_for(attempt:, exception:)
      retry_after_seconds = retry_after_seconds_for(exception)
      return [ [retry_after_seconds, openai_retry_max_delay_seconds].min, true ] if retry_after_seconds

      [ jittered_backoff_delay(attempt), false ]
    end

    def retry_after_seconds_for(exception)
      headers = faraday_response_headers(exception)
      value = headers["retry-after"] || headers["Retry-After"]
      return nil if value.blank?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def faraday_response_headers(exception)
      response = exception.respond_to?(:response) ? exception.response : nil
      return {} unless response.is_a?(Hash)

      direct = response[:headers] || response["headers"]
      nested = response.dig(:response, :headers) || response.dig("response", "headers")
      normalize_headers(direct || nested || {})
    end

    def normalize_headers(headers)
      return {} unless headers.respond_to?(:each)

      headers.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

    def jittered_backoff_delay(attempt)
      ceiling = [ openai_retry_base_delay_seconds * (2**(attempt - 1)), openai_retry_max_delay_seconds ].min
      rand * ceiling
    end

    def log_retry(call_type:, model:, attempt:, exception:, delay:, retry_after:)
      Rails.logger.warn(
        "[DungeonMaster::AiClient] #{call_type} #{exception.class} " \
        "(attempt #{attempt}/#{openai_max_retries + 1}, model=#{model}, delay=#{format('%.3f', delay)}s, retry_after=#{retry_after})"
      )
    end

    def openai_max_retries
      ENV.fetch("DM_OPENAI_MAX_RETRIES", DEFAULT_MAX_RETRIES.to_s).to_i
    end

    def openai_retry_base_delay_seconds
      ENV.fetch("DM_OPENAI_RETRY_BASE_DELAY_SECONDS", DEFAULT_RETRY_BASE_DELAY_SECONDS.to_s).to_f
    end

    def openai_retry_max_delay_seconds
      ENV.fetch("DM_OPENAI_RETRY_MAX_DELAY_SECONDS", DEFAULT_RETRY_MAX_DELAY_SECONDS.to_s).to_f
    end

    def custom_temperature?
      BigDecimal(@config.temperature.to_s) != BigDecimal('1.0')
    end
  end
end
