# frozen_string_literal: true

module DungeonMaster
  module Lore
    # `parsed_response:` payloads for the narrative-facts pipeline events
    # visible in Admin > Play Logs. Each class is the structured
    # description of exactly one `play_log!` event_type, so its supported
    # keys are discoverable without grep-diving the writer.
    #
    # Precedent: `DungeonMaster::PipelineFlowResults` (from PR #98) — one
    # namespace module, one class per variant, each exposes `#to_h`.
    module PlayLogEvents
      # Emitted per inserted row by `Lore::ApplyResults` on the write path.
      # event_type: "narrative_fact_stored".
      class StoredFact
        TEXT_PREVIEW_LENGTH = 200

        attr_reader :fact_id, :kind, :polarity, :source, :source_idx, :text

        def initialize(fact_id:, kind:, polarity:, source:, source_idx:, text:)
          @fact_id    = fact_id
          @kind       = kind
          @polarity   = polarity
          @source     = source
          @source_idx = source_idx
          @text       = text.to_s
        end

        def to_h
          {
            fact_id:    @fact_id,
            kind:       @kind,
            polarity:   @polarity,
            source:     @source,
            source_idx: @source_idx,
            text:       truncate(@text),
          }
        end

        private

        def truncate(text)
          text.length > TEXT_PREVIEW_LENGTH ? "#{text.first(TEXT_PREVIEW_LENGTH)}…" : text
        end
      end

      # Emitted per successful invalidation by `Lore::ApplyResults`.
      # event_type: "narrative_fact_invalidated".
      #
      # `replacement_fact_id` is the DB id of the replacement fact (resolved
      # from the `replacement_source_idx` against the just-inserted batch).
      # `replacement_source_idx` is the raw index Loremaster emitted — we
      # keep both so diff between emitted and resolved is observable.
      class InvalidatedFact
        attr_reader :fact_id, :replacement_fact_id, :replacement_source_idx, :reason

        def initialize(fact_id:, replacement_fact_id:, replacement_source_idx:, reason:)
          @fact_id                = fact_id
          @replacement_fact_id    = replacement_fact_id
          @replacement_source_idx = replacement_source_idx
          @reason                 = reason
        end

        def to_h
          {
            fact_id:                @fact_id,
            replacement_fact_id:    @replacement_fact_id,
            replacement_source_idx: @replacement_source_idx,
            reason:                 @reason,
          }
        end
      end

      # Emitted once per world-check read by `Lore::FactsLookup`.
      # event_type: "narrative_facts_retrieved".
      #
      # `hits` is an Array of already-slimmed hit hashes
      # (`{ fact_id:, kind:, distance: }`), intentionally smaller than the
      # full `FactHit` payload so the Admin card stays skimmable.
      class FactsRetrieved
        QUERY_PREVIEW_LENGTH = 120

        attr_reader :query_text, :limit, :hits

        def initialize(query_text:, limit:, hits:)
          @query_text = query_text.to_s
          @limit      = limit
          @hits       = hits
        end

        def to_h
          {
            query_preview: @query_text.truncate(QUERY_PREVIEW_LENGTH),
            limit:         @limit,
            hits:          @hits,
          }
        end
      end
    end
  end
end
