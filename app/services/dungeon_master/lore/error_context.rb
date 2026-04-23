# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Structured Sentry context bag for Loremaster read/write paths. Every
    # `@log.report_error(..., context: ...)` call from `Lore::ApplyResults`
    # and `Lore::FactsLookup` builds its context through this class so the
    # possible key set is discoverable in one place.
    #
    # Base fields (always present):
    #   step         — "loremaster" (write side) or "facts_lookup" (read side)
    #   adventure_id — Adventure under operation, or nil for seed errors.
    #   loop_id      — AdventureLoop under operation, or nil on seed.
    #   source       — "loremaster" | "seed" (the DB source tag of the
    #                  affected rows).
    #
    # Supported merge-in keys (passed to `#with`):
    #   source                 — overridden to a fine-grained string naming
    #                            the failure site (e.g. "apply_results.embeddings",
    #                            "apply_results.insert_fact",
    #                            "apply_results.invalidate_fact").
    #   fact_id                — AdventureNarrativeFact#id being operated on.
    #   source_idx             — Loremaster output index of the fact.
    #   replacement_source_idx — output index of the replacement fact (invalidation side).
    #   kind                   — fact kind at the moment of failure.
    #   text_preview           — first 80 chars of the fact text.
    #   texts_preview          — Array of previews (batched embedding side).
    #   query_preview          — truncated player intent (facts_lookup).
    #
    # `#with` returns a plain Hash so it drops straight into
    # `report_error(..., context: ctx.with(...))`.
    class ErrorContext
      def initialize(step:, adventure_id:, loop_id:, source:)
        @base = {
          step:         step,
          adventure_id: adventure_id,
          loop_id:      loop_id,
          source:       source,
        }.freeze
      end

      def with(**extra)
        @base.merge(extra)
      end

      def to_h
        @base.dup
      end
    end
  end
end
