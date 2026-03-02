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
      parts.any? ? parts.join("\n\n") : "=== CONTEXT ===\n(no active contexts — adventure just started)"
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
      if config.verbose?
        <<~PACING
          === PACING ===
          - You may write longer, more detailed responses when the scene calls for it.
          - Use rich descriptions, dialogue, and atmosphere.
          - Still end at a natural point where the player can act.
        PACING
      else
        <<~PACING
          === PACING ===
          - Keep each response SHORT: 1-2 paragraphs, roughly #{config.pacing_words_min}-#{config.pacing_words_max} words.
          - Be iterative: narrate one beat, then pause for the player to react.
          - Do NOT dump long exposition.
          - End each response at a natural decision point.
        PACING
      end
    end

    def directed_play_instructions(adventure)
      return "" unless adventure.directed_dm?

      <<~DIRECTED

        === DIRECTED PLAY STYLE ===
        The player has opted for a directed play style. You MUST:
        - Actively drive the story forward. Do not leave the player in open-ended
          situations without guidance.
        - End EVERY response with 2-3 concrete choices or suggestions for what
          the player can do next.
        - Be imperative: nudge the player toward meaningful action.
        - Keep the adventure moving. Avoid long pauses or scenes that drift.
      DIRECTED
    end
  end
end
