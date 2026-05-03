# frozen_string_literal: true

class AdventureLocation < ApplicationRecord
  SOURCES = %w[seed runtime].freeze

  belongs_to :adventure
  belongs_to :story_location, optional: true

  has_neighbors :embedding, dimensions: 1536

  validates :name,   presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :x,      numericality: true
  validates :y,      numericality: true

  scope :for_adventure, ->(adventure) { where(adventure_id: adventure.id) }
  scope :nearest_for, ->(adventure, embedding, limit:) {
    for_adventure(adventure)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
  }
end
