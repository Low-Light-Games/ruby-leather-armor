# frozen_string_literal: true

module Maps
  class PlaceLocations
    GOLDEN_ANGLE_RADIANS   = Math::PI * (3.0 - Math.sqrt(5.0))
    SPIRAL_RADIUS_PER_STEP = 5.0

    SEED_SCRAMBLER         = 2_654_435_761
    SEED_SCRAMBLER_MODULUS = 4_294_967_296

    def self.call(count:, seed:)
      new(count: count, seed: seed).call
    end

    def initialize(count:, seed:)
      @total_locations = count
      @story_seed      = seed
    end

    def call
      Array.new(@total_locations) { |position_index| place_at(position_index) }
    end

    private

    def place_at(position_index)
      polar_to_cartesian(
        angle:  polar_angle_for(position_index),
        radius: polar_radius_for(position_index),
      )
    end

    def polar_angle_for(position_index)
      position_index * GOLDEN_ANGLE_RADIANS + pattern_rotation_radians
    end

    def polar_radius_for(position_index)
      Math.sqrt(position_index) * SPIRAL_RADIUS_PER_STEP
    end

    def polar_to_cartesian(angle:, radius:)
      [radius * Math.cos(angle), radius * Math.sin(angle)]
    end

    def pattern_rotation_radians
      return 0.0 if @story_seed.nil?

      seed_as_unit_interval * 2 * Math::PI
    end

    def seed_as_unit_interval
      scrambled_seed / SEED_SCRAMBLER_MODULUS.to_f
    end

    def scrambled_seed
      (@story_seed.to_i * SEED_SCRAMBLER) & (SEED_SCRAMBLER_MODULUS - 1)
    end
  end
end
