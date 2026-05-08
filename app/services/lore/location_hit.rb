# frozen_string_literal: true

module Lore
  class LocationHit
    attr_reader :location_id, :name, :x, :y, :distance

    def initialize(location_id:, name:, x:, y:, distance:)
      @location_id = location_id
      @name        = name
      @x           = x
      @y           = y
      @distance    = distance
    end

    def to_h
      {
        location_id: @location_id,
        name:        @name,
        x:           @x,
        y:           @y,
        distance:    @distance,
      }
    end

    def self.from_row(row)
      new(
        location_id: row.id,
        name:        row.name,
        x:           row.x,
        y:           row.y,
        distance:    row.neighbor_distance,
      )
    end
  end
end
