# frozen_string_literal: true

module DungeonMaster
  # Shared formatting helpers used by pipeline steps when assembling
  # prompt locals before rendering an ERB template.
  module PromptHelpers
    module_function

    def build_micro_contexts_block(adventure)
      parts = []
      if adventure.traversal_context.present?
        parts << "=== TRAVERSAL CONTEXT ===\n#{adventure.traversal_context.to_json}"
      end
      if adventure.combat_context.present?
        parts << "=== COMBAT CONTEXT ===\n#{adventure.combat_context.to_json}"
      end
      if adventure.social_context.present?
        parts << "=== SOCIAL CONTEXT ===\n#{adventure.social_context.to_json}"
      end
      parts.any? ? parts.join("\n\n") : "=== CONTEXT ===\n(no active contexts — adventure just started)"
    end

    def format_contexts(micro_contexts)
      parts = []
      parts << "Traversal: #{micro_contexts[:traversal].present? ? micro_contexts[:traversal].to_json : '(none)'}"
      parts << "Combat: #{micro_contexts[:combat].present? ? micro_contexts[:combat].to_json : '(none)'}"
      parts << "Social: #{micro_contexts[:social].present? ? micro_contexts[:social].to_json : '(none)'}"
      parts.join("\n")
    end

    def format_manifest(manifest)
      manifest.group_by { |e| e[:domain] }.map do |domain, entries|
        slugs = entries.map { |e| "  - #{e[:slug]}: #{e[:name]}" }.join("\n")
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
