# frozen_string_literal: true

module PlayerTurn
  module Steps
    module EvaluatorTransport
      class RetryableEvaluatorError < StandardError; end

      DEFAULT_EVALUATOR_HTTP_MAX_RETRIES = 2
      DEFAULT_EVALUATOR_HTTP_RETRY_BASE_DELAY_SECONDS = 0.25
      DEFAULT_EVALUATOR_HTTP_RETRY_MAX_DELAY_SECONDS = 1.0

      private

      def evaluator_fan_out_results_by_step(results)
        Array(results).each_with_object({}) do |r, h|
          step = r.dig("meta", "step").to_s
          if step.blank?
            raise Ai::Error, "Evaluator fan_out returned a result without meta.step"
          end
          if h.key?(step)
            raise Ai::Error, "Evaluator fan_out returned duplicate meta.step #{step.inspect}"
          end

          h[step] = r
        end
      end

      def evaluator_fan_out_result!(by_step, step, phase)
        by_step[step] || raise(Ai::Error, "Evaluator #{phase} fan_out missing result for meta.step #{step.inspect}")
      end

      def evaluator_fan_out!(payloads, intention, phase:)
        by_step = evaluator_fan_out_results_by_step(
          call_evaluator!("#{evaluator_base_url}/fan_out", payloads, intention, phase: phase))
        retry_parse_error_prompts!(by_step, payloads, intention, phase: phase)
        by_step
      end

      def retry_parse_error_prompts!(by_step, original_payloads, intention, phase:)
        failed_steps = by_step.select { |_step, result| result["parse_status"] == "parse_error" }.keys
        return if failed_steps.empty?

        failed_steps.each do |step|
          payload = payload_for_step(original_payloads, step)
          next unless payload

          @log&.play_log!(
            "parse_retry",
            "Evaluator #{phase}/#{step}: parse_error on attempt 1, retrying once",
            parsed_response: { phase: phase, step: step }
          )

          retry_results = call_evaluator!(
            "#{evaluator_base_url}/fan_out",
            [payload], intention, phase: "#{phase}_retry"
          )
          retry_by_step = evaluator_fan_out_results_by_step(retry_results)
          retried = retry_by_step[step]
          next unless retried

          next if retried["parse_status"] == "parse_error"

          by_step[step] = retried
        end
      end

      def payload_for_step(payloads, step)
        Array(payloads).find do |payload|
          meta = payload[:meta] || payload["meta"] || {}
          (meta[:step] || meta["step"]).to_s == step
        end
      end

      def evaluator_base_url
        ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")
      end

      def call_evaluator!(url, prompts, intention, phase:)
        attempt = 0

        begin
          attempt += 1
          send_evaluator_request!(url, prompts, intention, phase: phase, attempt: attempt)
        rescue RetryableEvaluatorError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
               Net::OpenTimeout, Net::ReadTimeout, SocketError => e
          raise Ai::Error, "Evaluator #{phase} failed: #{e.message}" if attempt > evaluator_http_max_retries

          log_evaluator_retry(phase, attempt, e.class == RetryableEvaluatorError ? e.message : e.class.to_s)
          sleep(jittered_evaluator_http_retry_delay(attempt))
          retry
        end
      end

      def send_evaluator_request!(url, prompts, intention, phase:, attempt:)
        uri  = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 240
        http.open_timeout = 5

        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request.body = prompts.to_json
        response = http.request(request)

        begin
          body = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise Ai::Error, "Evaluator #{phase} returned non-JSON body (HTTP #{response.code}): #{e.message} — raw: #{response.body.truncate(500)}"
        end

        if response.code.to_i >= 500 && attempt <= evaluator_http_max_retries
          raise RetryableEvaluatorError, "HTTP #{response.code}: #{body.dig('error')&.truncate(120)}"
        end

        if response.code.to_i >= 400
          persist_partial_logs(Array(body.dig("partial_results")), intention)
          persist_evaluator_failure_log(phase, body)
          raise Ai::Error, "Evaluator #{phase} failed (HTTP #{response.code}): #{body.dig('error') || response.body.truncate(500)}"
        end

        persist_node_logs(Array(body), intention)
        body
      end

      def log_evaluator_retry(phase, attempt, reason)
        Rails.logger.warn(
          "[EvaluatorTransport] retrying #{phase} (#{reason}) " \
          "attempt #{attempt}/#{evaluator_http_max_retries + 1}"
        )
      end

      def persist_evaluator_failure_log(phase, body)
        return unless @log

        failures = Array(body["failures"]).map do |f|
          f.is_a?(Hash) ? f.deep_stringify_keys : { "raw" => f.to_s }
        end
        return if failures.empty?

        summary = failures.first(2).map do |f|
          "#{f['domain']} #{f['error_name'] || 'Error'} #{f['attempts']}/#{f['max_attempts']}".strip
        end.join("; ").truncate(200)

        @log.play_log!(
          "evaluator_fan_out_failure",
          "Evaluator #{phase} failure: #{summary}",
          parsed_response: { phase: phase, failures: failures, failed_steps: Array(body["failed_steps"]) },
        )
      rescue StandardError => e
        Rails.logger.warn("[EvaluatorTransport] failure-log persist failed: #{e.message}")
      end

      def persist_node_logs(results, intention)
        results.each do |result|
          meta = result["meta"] || {}
          step = meta["step"] || "unknown"
          domain = meta["domain"]
          summary = domain ? "#{step.titleize} [#{domain}]: \"#{@log.truncate(intention)}\"" : "#{step.titleize}: \"#{@log.truncate(intention)}\""

          usage_raw = result["usage"] || {}
          usage = {
            input_tokens:     usage_raw["input_tokens"].to_i,
            output_tokens:    usage_raw["output_tokens"].to_i,
            reasoning_tokens: usage_raw["reasoning_tokens"].to_i,
            total_tokens:     usage_raw["total_tokens"].to_i
          }

          @log.ai_log!(
            step,
            summary,
            result["raw_response"],
            result["parsed_response"],
            parse_status:  result["parse_status"] || "success",
            request_body:  result["request_body"],
            model_used:    result["model_used"],
            duration_ms:   result["duration_ms"],
            usage:         usage
          )
        end
      end

      def persist_partial_logs(partial_results, intention)
        persist_node_logs(partial_results, intention) if partial_results.any?
      end

      def evaluator_http_max_retries
        ENV.fetch("DM_EVALUATOR_HTTP_MAX_RETRIES", DEFAULT_EVALUATOR_HTTP_MAX_RETRIES.to_s).to_i
      end

      def evaluator_http_retry_base_delay_seconds
        ENV.fetch("DM_EVALUATOR_HTTP_RETRY_BASE_DELAY_SECONDS",
                  DEFAULT_EVALUATOR_HTTP_RETRY_BASE_DELAY_SECONDS.to_s).to_f
      end

      def evaluator_http_retry_max_delay_seconds
        ENV.fetch("DM_EVALUATOR_HTTP_RETRY_MAX_DELAY_SECONDS",
                  DEFAULT_EVALUATOR_HTTP_RETRY_MAX_DELAY_SECONDS.to_s).to_f
      end

      def jittered_evaluator_http_retry_delay(attempt)
        ceiling = [ evaluator_http_retry_base_delay_seconds * (2**(attempt - 1)),
                    evaluator_http_retry_max_delay_seconds ].min
        rand * ceiling
      end
    end
  end
end
