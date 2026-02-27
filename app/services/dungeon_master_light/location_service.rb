# frozen_string_literal: true

module DungeonMasterLight
  # Manages location tracking and traversal for the Light DM system.
  # All distances are persisted once (AI decides, app stores), then used
  # deterministically for travel time calculations.
  class LocationService
    TERRAIN_SPEED_MULTIPLIERS = {
      "road" => 1.0,
      "urban" => 1.0,
      "plains" => 0.9,
      "forest" => 0.5,
      "hills" => 0.5,
      "mountain" => 0.3,
      "swamp" => 0.3,
      "dungeon" => 0.7,
      "desert" => 0.6,
      "snow" => 0.4
    }.freeze

    BASE_MILES_PER_HOUR = 3.0

    def initialize(adventure)
      @adventure = adventure
    end

    # Idempotent location creation.
    # @return [Location]
    def find_or_create(name:, terrain: "road", description: nil)
      @adventure.locations.find_or_create_by!(name: name) do |loc|
        loc.terrain_type = terrain
        loc.description = description
      end
    end

    # Persist a distance between two locations (graph edge).
    # Bidirectional: querying either direction returns the same distance.
    # @return [LocationEdge]
    def set_distance(from:, to:, miles:, terrain: "road", description: nil)
      from_loc = find_or_create(name: from, terrain: terrain)
      to_loc = find_or_create(name: to, terrain: terrain)

      edge = LocationEdge.find_by(from_location: from_loc, to_location: to_loc)
      edge ||= LocationEdge.find_by(from_location: to_loc, to_location: from_loc)

      if edge
        edge.update!(distance_miles: miles, terrain_type: terrain, description: description) if edge.distance_miles != miles
        edge
      else
        LocationEdge.create!(
          from_location: from_loc,
          to_location: to_loc,
          distance_miles: miles,
          terrain_type: terrain,
          description: description
        )
      end
    end

    # @return [Location, nil]
    def current_location
      @adventure.current_location
    end

    # Move the party to a destination. Calculates travel time based on
    # character speed, encumbrance, and terrain.
    #
    # @param to [String] destination location name
    # @return [Hash] { destination:, distance_miles:, travel_hours:, terrain: }
    def move_party(to:)
      destination = @adventure.locations.find_by(name: to)
      return { error: "Unknown destination: #{to}" } unless destination

      current = current_location
      @adventure.locations.where(is_current: true).update_all(is_current: false)
      destination.update!(is_current: true)

      result = { destination: destination.name, terrain: destination.terrain_type }

      if current
        distance = current.distance_to(destination)
        if distance
          travel_hours = calculate_travel_time(distance, destination.terrain_type)
          result.merge!(distance_miles: distance.to_f, travel_hours: travel_hours.round(1))
        end
      end

      result
    end

    # Query the persisted distance between two locations.
    # @return [Float, nil]
    def distance_between(from_name, to_name)
      from_loc = @adventure.locations.find_by(name: from_name)
      to_loc = @adventure.locations.find_by(name: to_name)
      return nil unless from_loc && to_loc

      from_loc.distance_to(to_loc)&.to_f
    end

    private

    def calculate_travel_time(distance_miles, terrain_type)
      sheet = @adventure.adventure_sheets.first
      speed_ft = sheet&.derived_stats&.dig("speed") || 30

      miles_per_hour = (speed_ft / 30.0) * BASE_MILES_PER_HOUR
      terrain_mult = TERRAIN_SPEED_MULTIPLIERS[terrain_type] || 0.7
      effective_speed = miles_per_hour * terrain_mult

      effective_speed > 0 ? distance_miles.to_f / effective_speed : 999.0
    end
  end
end
