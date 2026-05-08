# frozen_string_literal: true

module Combat
  class Position
    attr_reader :token_id, :label, :coordinates, :type, :creature_sheet_id

    def initialize(token_id:, label:, coordinates: { x: nil, y: nil }, type: nil, creature_sheet_id: nil)
      @token_id = token_id
      @label = label
      @coordinates = (coordinates || {}).to_h
      @type = type
      @creature_sheet_id = creature_sheet_id
    end

    def x
      coordinates[:x] || coordinates['x']
    end

    def y
      coordinates[:y] || coordinates['y']
    end

    def coordinates_present?
      !x.nil? && !y.nil?
    end

    def distance_to(other)
      return Float::INFINITY unless coordinates_present? && other&.coordinates_present?

      [(x.to_i - other.x.to_i).abs, (y.to_i - other.y.to_i).abs].max
    end
  end
end
