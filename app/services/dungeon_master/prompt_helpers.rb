# frozen_string_literal: true

module DungeonMaster
  # Shared formatting helpers used by pipeline steps when assembling
  # prompt locals before rendering an ERB template.
  module PromptHelpers
    module_function

    CONTEXT_FIELDS = %w[traversal combat social exploration rest inventory].freeze

    def all_micro_contexts(adventure)
      CONTEXT_FIELDS.each_with_object({}) do |field, h|
        h[field.to_sym] = adventure.send("#{field}_context")
      end
    end

    def build_micro_contexts_block(adventure)
      parts = CONTEXT_FIELDS.filter_map do |field|
        ctx = adventure.send("#{field}_context")
        "=== #{field.upcase} CONTEXT ===\n#{ctx.to_json}" if ctx.present?
      end
      parts.any? ? parts.join("\n\n") : nil
    end

    def format_contexts(micro_contexts)
      CONTEXT_FIELDS.map do |field|
        ctx = micro_contexts[field.to_sym]
        "#{field.titleize}: #{ctx.present? ? ctx.to_json : '(none)'}"
      end.join("\n")
    end

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
