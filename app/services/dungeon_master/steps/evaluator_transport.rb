# frozen_string_literal: true

module DungeonMaster
  module Steps
    # HTTP client for the Node evaluator microservice (/fan_out, /sequential).
    # Included by ParallelEvaluation so all pipeline steps can batch LLM calls
    # without Ruby Thread.new.
    module EvaluatorTransport
      DEFAULT_EVALUATOR_HTTP_MAX_RETRIES = 1
      DEFAULT_EVALUATOR_HTTP_RETRY_BASE_DELAY_SECONDS = 0.25
      DEFAULT_EVALUATOR_HTTP_RETRY_MAX_DELAY_SECONDS = 1.0

      private

      # POST /fan_out returns one result per prompt in the same order as the request body
      # (see evaluator/src/index.js — results are pushed in index order, not completion order).
      # We still index by meta["step"] so callers do not rely on array position alone.
      def evaluator_fan_out_results_by_step(results)
        Array(results).each_with_object({}) do |r, h|
          step = r.dig("meta", "step").to_s
          if step.blank?
            raise AiError, "Evaluator fan_out returned a result without meta.step"
          end
          if h.key?(step)
            raise AiError, "Evaluator fan_out returned duplicate meta.step #{step.inspect}"
          end

          h[step] = r
        end
      end

      def evaluator_fan_out_result!(by_step, step, phase)
        by_step[step] || raise(AiError, "Evaluator #{phase} fan_out missing result for meta.step #{step.inspect}")
      end

      # POST /fan_out — returns results indexed by meta["step"].
      # Use this instead of wiring evaluator_base_url + call_evaluator! + evaluator_fan_out_results_by_step.
      def evaluator_fan_out!(payloads, intention, phase:)
        evaluator_fan_out_results_by_step(
          call_evaluator!("#{evaluator_base_url}/fan_out", payloads, intention, phase: phase))
      end

      # POST /sequential — results returned in request order (no step indexing).
      def evaluator_sequential!(payloads, intention, phase:)
        call_evaluator!("#{evaluator_base_url}/sequential", payloads, intention, phase: phase)
      end

      def evaluator_base_url
        ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")
      end

      def call_evaluator!(url, prompts, intention, phase:)
        attempt = 0

        begin
          attempt += 1
          uri  = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.read_timeout = 150
          http.open_timeout = 5

          request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
          request.body = prompts.to_json

          response = http.request(request)

          begin
            body = JSON.parse(response.body)
          rescue JSON::ParserError => e
            raise AiError, "Evaluator #{phase} returned non-JSON body (HTTP #{response.code}): #{e.message} — raw: #{response.body.truncate(500)}"
          end

          if response.code.to_i >= 400
            persist_partial_logs(Array(body.dig("partial_results")), intention)
            raise AiError, "Evaluator #{phase} failed (HTTP #{response.code}): #{body.dig('error') || response.body.truncate(500)}"
          end

          persist_node_logs(Array(body), intention)
          body
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Net::OpenTimeout, SocketError => e
          raise AiError, "Evaluator unreachable during #{phase}: #{e.message}" if attempt > evaluator_http_max_retries

          delay = jittered_evaluator_http_retry_delay(attempt)
          Rails.logger.warn(
            "[EvaluatorTransport] #{e.class} during #{phase} " \
            "(attempt #{attempt}/#{evaluator_http_max_retries + 1}, delay=#{format('%.3f', delay)}s)"
          )
          sleep(delay)
          retry
        rescue Net::ReadTimeout => e
          raise AiError, "Evaluator unreachable during #{phase}: #{e.message}"
        end
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
