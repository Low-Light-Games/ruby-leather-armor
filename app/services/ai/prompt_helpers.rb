# frozen_string_literal: true

module Ai
  module PromptHelpers
    module_function

    def format_manifest(manifest)
      manifest.group_by { |e| e[:domain] }.map do |domain, entries|
        slugs = entries.map do |e|
          line = "  - #{e[:slug]}: #{e[:name]}"
          line += " — #{e[:brief]}" if e[:brief].present?
          line
        end.join("\n")
        "[#{domain}]\n#{slugs}"
      end.join("\n")
    end

    def pacing_instructions(config)
      PromptRenderer.render_partial("narrate/_pacing",
        words_min: config.pacing_words_min,
        words_max: config.pacing_words_max)
    end

    def directed_play_instructions(adventure)
      return "" unless adventure.directed_dm?

      PromptRenderer.render_partial("narrate/_directed_play")
    end
  end
end
