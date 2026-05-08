# frozen_string_literal: true

module DungeonMaster
  module Lore
    # TODO: Improve readability — value object whose attr_reader list already encodes the shape; the prose preamble is redundant.
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
