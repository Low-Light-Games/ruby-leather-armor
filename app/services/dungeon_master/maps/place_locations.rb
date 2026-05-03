# frozen_string_literal: true

module DungeonMaster
  module Maps
    # Vogel-spiral placement: deterministic, evenly-distributed coordinates
    # for N points on a 2D plane. Per-story seed offset so different stories
    # produce different layouts; same story always reproduces the same map.
    class PlaceLocations
      GOLDEN_ANGLE  = Math::PI * (3.0 - Math.sqrt(5.0))
      RADIUS_FACTOR = 5.0

      def self.call(count:, seed:)
        new(count: count, seed: seed).call
      end

      def initialize(count:, seed:)
        @count = count
        @seed  = seed
      end

      def call
        offset = seed_offset
        Array.new(@count) do |idx|
          angle  = idx * GOLDEN_ANGLE + offset
          radius = Math.sqrt(idx) * RADIUS_FACTOR
          [radius * Math.cos(angle), radius * Math.sin(angle)]
        end
      end

      private

      def seed_offset
        return 0.0 if @seed.nil?

        (@seed.to_i.hash.abs % 1_000_000) / 1_000_000.0 * 2 * Math::PI
      end
    end
  end
end
