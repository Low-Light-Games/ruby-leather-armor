# frozen_string_literal: true

module PlayerTurn
  module Steps
    module GameMaster
      class Reasoning
        SHORT_LABELS = {
          "engaging_the_player" => "engage",
          "tool_calls" => "tools",
          "adventure_state" => "state"
        }.freeze

        def self.from_parsed(value)
          new(value)
        end

        def initialize(raw)
          @raw = raw
        end

        def to_h
          case @raw
          when Hash then @raw.transform_keys(&:to_s)
          when String then { "summary" => @raw }
          else { "summary" => @raw.to_s }
          end
        end

        def display_summary
          case @raw
          when Hash then summary_from_hash
          when String then @raw
          else @raw.to_s
          end
        end

        private

        def summary_from_hash
          parts = @raw.filter_map do |key, value|
            text = value.to_s.strip
            next if text.empty?

            "#{short_label(key)}: #{text.truncate(80)}"
          end
          parts.empty? ? "(empty reasoning)" : parts.join("; ")
        end

        def short_label(key)
          SHORT_LABELS.fetch(key.to_s, key.to_s.split("_").first)
        end
      end
    end
  end
end
