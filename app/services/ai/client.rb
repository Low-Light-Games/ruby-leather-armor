# frozen_string_literal: true

require 'bigdecimal'

module Ai
  class Client
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_RETRY_BASE_DELAY_SECONDS = 0.5
    DEFAULT_RETRY_MAX_DELAY_SECONDS = 8.0

    attr_reader :last_failed_raw_response, :last_parse_status, :last_model_used, :last_usage, :last_reasoning_effort

    def initialize(config)
      @client = OpenAI::Client.new
      @config = config
      @default_model = config.model
      @last_failed_raw_response = nil
      @last_parse_status = nil
      @last_model_used = nil
      @last_usage = nil
    end

    def chat(system_prompt:, user_message: nil, messages: nil, step_name: nil, model: nil, reasoning_effort: nil)
      @last_usage = nil
      effective_model = model || @default_model
      @last_model_used = effective_model
      @last_reasoning_effort = reasoning_effort

      params = chat_parameters(
        model: effective_model,
        messages: chat_messages(system_prompt, user_message, messages),
        reasoning_effort: reasoning_effort
      )
      response = request_chat_completion(params, effective_model)
      raise Error, response.dig("error", "message") || "OpenAI API error" if response.dig("error")

      content       = response.dig("choices", 0, "message", "content")
      finish_reason = response.dig("choices", 0, "finish_reason")
      @last_usage = chat_usage(response["usage"]) if response["usage"]
      ensure_complete_content!(content, finish_reason, step_name)

      content
    end

    def embeddings(texts:, model:, dimensions: nil)
      raise Error, "embeddings called with no texts" if texts.nil? || texts.empty?

      params = { model: model, input: texts }
      params[:dimensions] = dimensions if dimensions

      response = request_embeddings(params, model)
      if response.is_a?(Hash) && response.dig("error")
        raise Error, response.dig("error", "message") || "OpenAI embeddings API error"
      end

      data = response.is_a?(Hash) ? response["data"] : nil
      unless data.is_a?(Array) && data.length == texts.length
        raise Error, "Unexpected embeddings response shape (got #{data&.length || 'nil'} vectors for #{texts.length} texts)"
      end

      prompt_tokens = (response["usage"] || {})["prompt_tokens"].to_i
      @last_usage = {
        input_tokens:     prompt_tokens,
        output_tokens:    0,
        reasoning_tokens: 0,
        total_tokens:     prompt_tokens,
      }

      data.sort_by { |row| row["index"].to_i }.map { |row| row["embedding"] }
    end

    def parse_json(raw, fallback_as: nil)
      @last_parse_status = "success"

      cleaned = raw.strip
        .gsub(/\A```(?:json)?\s*/, "")
        .gsub(/\s*```\z/, "")
        .strip

      JSON.parse(cleaned)
    rescue JSON::ParserError
      Rails.logger.warn(
        "[Ai::Client] JSON parse failed. " \
        "Raw (first 500 chars): #{raw&.first(500)}"
      )

      if fallback_as == :dm_response && cleaned.present?
        Rails.logger.info("[Ai::Client] Falling back: treating raw response as narrative text")
        @last_parse_status = "parse_fallback"
        { "narrative" => cleaned }
      else
        @last_parse_status = "parse_error"
        raise Error, "Failed to parse AI response as JSON"
      end
    end

    private

    def chat_messages(system_prompt, user_message, messages)
      chat_messages = [{ role: "system", content: system_prompt }]
      if messages
        chat_messages.concat(messages)
      elsif user_message
        chat_messages << { role: "user", content: user_message }
      end
      chat_messages
    end

    def chat_parameters(model:, messages:, reasoning_effort:)
      params = { model: model, messages: messages, response_format: { type: "json_object" } }
      if OpenaiModelCatalog.supports_temperature?(model) && custom_temperature?
        params[:temperature] = @config.temperature
      end
      if reasoning_effort.present? && OpenaiModelCatalog.reasoning_model?(model)
        params[:reasoning_effort] = reasoning_effort
      end
      params
    end

    def request_chat_completion(params, model)
      with_openai_retries(call_type: "chat", model: model) do
        @client.chat(parameters: params)
      end
    rescue Faraday::BadRequestError => e
      message = bad_request_message(e)
      Rails.logger.error("[Ai::Client] Bad request: #{message}")
      raise Error, "AI request rejected: #{message}"
    rescue Faraday::TooManyRequestsError => e
      Rails.logger.error("[Ai::Client] Rate limited after #{openai_max_retries + 1} attempts: #{e.message}")
      raise Error, "Rate limited by OpenAI after #{openai_max_retries + 1} attempts"
    rescue Faraday::ClientError => e
      Rails.logger.error("[Ai::Client] #{e.class}: #{e.message}")
      raise Error, "AI request rejected: #{e.message}"
    rescue Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
      Rails.logger.error("[Ai::Client] #{e.class} after #{openai_max_retries + 1} attempts: #{e.message}")
      raise Error, "Could not reach the AI service after #{openai_max_retries + 1} attempts. Please try again shortly."
    end

    def request_embeddings(params, model)
      with_openai_retries(call_type: "embeddings", model: model) do
        @client.embeddings(parameters: params)
      end
    rescue Faraday::BadRequestError => e
      message = bad_request_message(e)
      Rails.logger.error("[Ai::Client] Embeddings bad request: #{message}")
      raise Error, "AI embeddings request rejected: #{message}"
    rescue Faraday::TooManyRequestsError => e
      Rails.logger.error("[Ai::Client] Embeddings rate limited after #{openai_max_retries + 1} attempts: #{e.message}")
      raise Error, "Embeddings rate limited by OpenAI after #{openai_max_retries + 1} attempts"
    rescue Faraday::ClientError => e
      Rails.logger.error("[Ai::Client] Embeddings #{e.class}: #{e.message}")
      raise Error, "AI embeddings request rejected: #{e.message}"
    rescue Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
      Rails.logger.error("[Ai::Client] Embeddings #{e.class} after #{openai_max_retries + 1} attempts: #{e.message}")
      raise Error, "Could not reach the AI embeddings service after #{openai_max_retries + 1} attempts."
    end

    def bad_request_message(error)
      body = begin
        error.response&.dig(:body)
      rescue StandardError
        nil
      end
      body.is_a?(Hash) ? body.dig("error", "message") : error.message
    end

    def chat_usage(usage)
      {
        input_tokens: usage["prompt_tokens"] || 0,
        output_tokens: usage["completion_tokens"] || 0,
        reasoning_tokens: usage.dig("completion_tokens_details", "reasoning_tokens") || 0,
        total_tokens: usage["total_tokens"] || 0
      }
    end

    def ensure_complete_content!(content, finish_reason, step_name)
      if finish_reason == "length"
        label = step_name || "unknown"
        @last_failed_raw_response = content
        Rails.logger.error(
          "[Ai::Client] Token limit hit on '#{label}' step " \
          "(finish_reason: length, content_length: #{content&.length || 0})"
        )
        raise TokenBudgetExceededError.new(step_name: label, budget: nil)
      end

      return unless content.nil? || content.strip.empty?

      @last_failed_raw_response = content
      raise Error, "Empty response from AI (finish_reason: #{finish_reason || 'unknown'})"
    end

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
        "[Ai::Client] #{call_type} #{exception.class} " \
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
