# frozen_string_literal: true

module Lore
  class NpcHit
    attr_reader :npc_id, :name, :attitude, :location_name, :distance

    def initialize(npc_id:, name:, attitude:, location_name:, distance:)
      @npc_id        = npc_id
      @name          = name
      @attitude      = attitude
      @location_name = location_name
      @distance      = distance
    end

    def to_h
      {
        npc_id:        @npc_id,
        name:          @name,
        attitude:      @attitude,
        location_name: @location_name,
        distance:      @distance,
      }
    end

    def self.from_row(row)
      new(
        npc_id:        row.id,
        name:          row.name,
        attitude:      row.attitude,
        location_name: row.location_name,
        distance:      row.neighbor_distance,
      )
    end
  end
end
