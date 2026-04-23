# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Single retrieval result returned by `Lore::FactsLookup`. Consumers
    # (sanity_checker_world prompt renderer, Admin retrieval panel) work
    # off the hash form via `#to_h`, so the key set is the contract.
    #
    # Shape:
    #   fact_id  — Integer, AdventureNarrativeFact#id.
    #   text     — String, the stored fact text (not truncated — the
    #              prompt renderer decides how to fit it).
    #   kind     — "event" | "state" | "entity".
    #   polarity — "asserts" | "negates".
    #   distance — Float, cosine distance from the query embedding
    #              (smaller is closer).
    class FactHit
      attr_reader :fact_id, :text, :kind, :polarity, :distance

      def initialize(fact_id:, text:, kind:, polarity:, distance:)
        @fact_id  = fact_id
        @text     = text
        @kind     = kind
        @polarity = polarity
        @distance = distance
      end

      def to_h
        {
          fact_id:  @fact_id,
          text:     @text,
          kind:     @kind,
          polarity: @polarity,
          distance: @distance,
        }
      end

      def self.from_row(row)
        new(
          fact_id:  row.id,
          text:     row.text,
          kind:     row.kind,
          polarity: row.polarity,
          distance: row.neighbor_distance,
        )
      end
    end
  end
end
