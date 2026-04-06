# frozen_string_literal: true

module DungeonMaster
  module Steps
    # HTTP client for the Node evaluator microservice (/fan_out, /sequential).
    # Included by ParallelEvaluation so all pipeline steps can batch LLM calls
    # without Ruby Thread.new.
    module EvaluatorTransport
      private

      def call_evaluator!(url, prompts, intention, phase:)
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
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::ReadTimeout, Net::OpenTimeout => e
        raise AiError, "Evaluator unreachable during #{phase}: #{e.message}"
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
    end
  end
end
