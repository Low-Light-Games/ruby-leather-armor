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
      # `hits` carries the resolved fact text per Decision 18 so the
      # Admin retrieval panel can render a hit without joining the
      # facts table manually.
      class FactsRetrieved
        QUERY_PREVIEW_LENGTH = 120
        TEXT_PREVIEW_LENGTH  = 200

        attr_reader :query_text, :limit, :hits

        def initialize(query_text:, limit:, hits:)
          @query_text = query_text.to_s
          @limit      = limit
          @hits       = hits
        end

        def to_h
          {
            kind:          "facts",
            query_preview: @query_text.truncate(QUERY_PREVIEW_LENGTH),
            limit:         @limit,
            hits:          @hits.map { |h| slim_hit(h) },
          }
        end

        private

        def slim_hit(hit)
          {
            fact_id:  hit[:fact_id],
            kind:     hit[:kind],
            distance: hit[:distance],
            text:     truncate_text(hit[:text]),
          }
        end

        def truncate_text(text)
          str = text.to_s
          str.length > TEXT_PREVIEW_LENGTH ? "#{str.first(TEXT_PREVIEW_LENGTH)}…" : str
        end
      end

      class NpcsRetrieved
        QUERY_PREVIEW_LENGTH = 120

        attr_reader :query_text, :limit, :hits

        def initialize(query_text:, limit:, hits:)
          @query_text = query_text.to_s
          @limit      = limit
          @hits       = hits
        end

        def to_h
          {
            kind:          "npcs",
            query_preview: @query_text.truncate(QUERY_PREVIEW_LENGTH),
            limit:         @limit,
            hits:          @hits.map { |h| slim_hit(h) },
          }
        end

        private

        def slim_hit(hit)
          {
            npc_id:        hit[:npc_id],
            name:          hit[:name],
            attitude:      hit[:attitude],
            location_name: hit[:location_name],
            distance:      hit[:distance],
          }
        end
      end

      class LocationsRetrieved
        QUERY_PREVIEW_LENGTH = 120

        attr_reader :query_text, :limit, :hits

        def initialize(query_text:, limit:, hits:)
          @query_text = query_text.to_s
          @limit      = limit
          @hits       = hits
        end

        def to_h
          {
            kind:          "locations",
            query_preview: @query_text.truncate(QUERY_PREVIEW_LENGTH),
            limit:         @limit,
            hits:          @hits.map { |h| slim_hit(h) },
          }
        end

        private

        def slim_hit(hit)
          {
            location_id: hit[:location_id],
            name:        hit[:name],
            x:           hit[:x],
            y:           hit[:y],
            distance:    hit[:distance],
          }
        end
      end
    end
  end
end
