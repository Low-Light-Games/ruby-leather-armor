# frozen_string_literal: true

module DungeonMaster
  module Lore
    class NpcsLookup < VectorLookup
      private

      def lookup_kind          = "npcs"
      def hit_class            = NpcHit
      def play_log_event_class = PlayLogEvents::NpcsRetrieved
      def play_log_event_type  = "adventure_npcs_retrieved"

      def query_neighbors(query_embedding)
        AdventureNpc.nearest_for(@adventure, query_embedding, limit: @limit)
      end
    end
  end
end
