# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Shared HTTP transport and logging for any pipeline step that calls the
    # Node evaluator microservice (either /fan_out or /sequential).
    #
    # Included in Pipeline alongside the other step modules.  Any step that
    # needs to POST prompts to the evaluator includes this module and calls:
    #
    #   call_evaluator!(url, prompts, label, phase:)  → Array of result hashes
    #
    # All duration data, usage, and parse status are persisted via @log by
    # persist_node_logs so that observability is identical whether the call
    # came from ParallelEvaluation, SanityChecker, ContextUpdate, or Stagehand.
    module NodeEvaluator
      private

      # Posts +prompts+ to +url+, handles errors and logging.
      # +label+ is a short string used only for log summaries (e.g. the action text).
      # Returns the parsed JSON body (Array of result hashes).
      def call_evaluator!(url, prompts, label, phase:)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        uri      = URI(url)
        http     = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 150
        http.open_timeout = 5

        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request.body = prompts.to_json

        response = http.request(request)
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        begin
          body = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise AiError, "Evaluator #{phase} returned non-JSON body (HTTP #{response.code}): #{e.message} — raw: #{response.body.truncate(500)}"
        end

        if response.code.to_i >= 400
          persist_partial_logs(Array(body.dig("partial_results")), label)
          raise AiError, "Evaluator #{phase} failed (HTTP #{response.code}): #{body.dig("error") || response.body.truncate(500)}"
        end

        persist_node_logs(Array(body), label)
        body
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::ReadTimeout, Net::OpenTimeout => e
        raise AiError, "Evaluator unreachable during #{phase}: #{e.message}"
      end

      def persist_node_logs(results, label)
        results.each do |result|
          meta   = result["meta"] || {}
          step   = meta["step"] || "unknown"
          domain = meta["domain"]
          summary = domain ? "#{step.titleize} [#{domain}]: \"#{@log.truncate(label)}\"" \
                           : "#{step.titleize}: \"#{@log.truncate(label)}\""

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

      def persist_partial_logs(partial_results, label)
        persist_node_logs(partial_results, label) if partial_results.any?
      end
    end
  end
end
