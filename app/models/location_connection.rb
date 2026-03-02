# frozen_string_literal: true

class LocationConnection < ApplicationRecord
  belongs_to :from_location, class_name: "StoryLocation"
  belongs_to :to_location,   class_name: "StoryLocation"

  validates :distance_miles, presence: true, numericality: { greater_than: 0 }
  validates :terrain_type, presence: true
  validates :from_location_id, uniqueness: { scope: :to_location_id,
    message: "connection already exists between these locations" }

  TERRAIN_TYPES = %w[road trail forest mountain swamp desert river coast urban underground].freeze

  validates :terrain_type, inclusion: { in: TERRAIN_TYPES }

  def involves?(location)
    from_location_id == location.id || to_location_id == location.id
  end

  def other_location(location)
    from_location_id == location.id ? to_location : from_location
  end
end
