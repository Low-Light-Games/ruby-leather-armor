# frozen_string_literal: true

module Lore
  class LocationsLookup < VectorLookup
    private

    def lookup_kind          = "locations"
    def hit_class            = LocationHit
    def play_log_event_class = PlayLogEvents::LocationsRetrieved
    def play_log_event_type  = "adventure_locations_retrieved"

    def query_neighbors(query_embedding)
      AdventureLocation.nearest_for(@adventure, query_embedding, limit: @limit)
    end
  end
end
