# frozen_string_literal: true

class LocationEdge < ApplicationRecord
  belongs_to :from_location, class_name: "Location"
  belongs_to :to_location, class_name: "Location"

  validates :distance_miles, presence: true, numericality: { greater_than: 0 }
  validates :from_location_id, uniqueness: { scope: :to_location_id }
end
