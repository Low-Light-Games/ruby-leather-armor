# frozen_string_literal: true

module DungeonMaster
  module Lore
    module PlayLogEvents
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
    end
  end
end
