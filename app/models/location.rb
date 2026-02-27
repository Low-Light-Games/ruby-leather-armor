# frozen_string_literal: true

class Location < ApplicationRecord
  belongs_to :adventure

  has_many :outgoing_edges, class_name: "LocationEdge", foreign_key: :from_location_id, dependent: :destroy
  has_many :incoming_edges, class_name: "LocationEdge", foreign_key: :to_location_id, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :adventure_id }

  scope :current, -> { where(is_current: true) }

  def distance_to(other_location)
    edge = LocationEdge.find_by(from_location_id: id, to_location_id: other_location.id)
    edge ||= LocationEdge.find_by(from_location_id: other_location.id, to_location_id: id)
    edge&.distance_miles
  end
end
