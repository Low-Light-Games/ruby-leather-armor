# frozen_string_literal: true

class StoryLocation < ApplicationRecord
  belongs_to :story

  has_many :connections_from, class_name: "LocationConnection",
           foreign_key: :from_location_id, dependent: :destroy
  has_many :connections_to, class_name: "LocationConnection",
           foreign_key: :to_location_id, dependent: :destroy

  accepts_nested_attributes_for :connections_from, allow_destroy: true

  validates :name, presence: true, uniqueness: { scope: :story_id }

  def connections
    LocationConnection.where("from_location_id = ? OR to_location_id = ?", id, id)
  end

  def distance_to(other)
    conn = LocationConnection.find_by(
      "from_location_id = ? AND to_location_id = ? OR from_location_id = ? AND to_location_id = ?",
      id, other.id, other.id, id
    )
    conn&.distance_miles
  end

  def connection_to(other)
    LocationConnection.find_by(
      "from_location_id = ? AND to_location_id = ? OR from_location_id = ? AND to_location_id = ?",
      id, other.id, other.id, id
    )
  end

  def neighbors
    from_ids = connections_from.pluck(:to_location_id)
    to_ids   = connections_to.pluck(:from_location_id)
    StoryLocation.where(id: (from_ids + to_ids).uniq)
  end
end
