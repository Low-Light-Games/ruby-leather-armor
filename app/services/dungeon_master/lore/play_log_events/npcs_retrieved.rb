# frozen_string_literal: true

module DungeonMaster
  module Lore
    module PlayLogEvents
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
    end
  end
end
