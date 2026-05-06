# frozen_string_literal: true

module DungeonMaster
  module Tools
    module Registry
      class ToolError < StandardError; end

      MAX_CALLS_PER_TURN = 1

      SUPPORTED = {
        "request_roll" => {
          required_args: %w[intent_text],
          dispatch: lambda { |engine, args|
            engine.send(:run_roll_request_as_ai_called_tool, args.fetch("intent_text"))
          }
        }
      }.freeze

      def self.dispatch(tool_calls, pipeline_engine:)
        validate_calls!(tool_calls)
        results = {}
        Array(tool_calls).each do |call|
          name = call["name"].to_s
          args = call["args"] || {}
          spec = SUPPORTED.fetch(name)
          results[name] = spec[:dispatch].call(pipeline_engine, args)
        end
        DispatchResult.new(request_roll_result: results["request_roll"])
      end

      def self.supported?(name)
        SUPPORTED.key?(name.to_s)
      end

      def self.validate_calls!(tool_calls)
        calls = Array(tool_calls)
        if calls.length > MAX_CALLS_PER_TURN
          raise ToolError, "too many tool calls (#{calls.length} > #{MAX_CALLS_PER_TURN})"
        end

        calls.each do |call|
          unless call.is_a?(Hash) && call["name"].is_a?(String)
            raise ToolError, "malformed tool call: #{call.inspect.truncate(80)}"
          end

          name = call["name"]
          spec = SUPPORTED[name] or raise ToolError, "unknown tool: #{name}"

          args = call["args"] || {}
          missing = spec[:required_args] - args.keys.map(&:to_s)
          raise ToolError, "missing args for #{name}: #{missing.inspect}" if missing.any?
        end
      end
    end
  end
end
