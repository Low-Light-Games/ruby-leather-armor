# frozen_string_literal: true

module Lore
  class FactsLookup < VectorLookup
    private

    def lookup_kind          = "facts"
    def hit_class            = FactHit
    def play_log_event_class = PlayLogEvents::FactsRetrieved
    def play_log_event_type  = "narrative_facts_retrieved"

    def play_log_summary(hits)
      "World check retrieved #{hits.length} fact(s) for intent"
    end

    def query_neighbors(query_embedding)
      AdventureNarrativeFact.nearest_active_for(@adventure, query_embedding, limit: @limit)
    end
  end
end
