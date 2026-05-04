# frozen_string_literal: true

# Per-adventure NPC, written by `Lore::ApplyNpcs` (sole writer; §18
# single-writer invariant for the new structured stores). Replaces
# the NPC-shaped reads previously served by `traversal_context` and
# `social_context`.
class AdventureNpc < ApplicationRecord
  ATTITUDES = %w[friendly indifferent unfriendly].freeze
  SOURCES   = %w[seed runtime].freeze

  belongs_to :adventure
  belongs_to :story_npc, optional: true
  belongs_to :last_seen_loop,
             class_name: "AdventureLoop",
             foreign_key: :last_seen_loop_id,
             optional: true

  has_neighbors :embedding, dimensions: 1536

  validates :name,     presence: true
  validates :attitude, inclusion: { in: ATTITUDES }
  validates :source,   inclusion: { in: SOURCES }

  scope :for_adventure, ->(adventure) { where(adventure_id: adventure.id) }
  scope :at_location,   ->(location_name) { where(location_name: location_name) }
  scope :hostile,       -> { where(attitude: "unfriendly") }
  scope :non_hostile,   -> { where.not(attitude: "unfriendly") }
  scope :nearest_for, ->(adventure, embedding, limit:) {
    for_adventure(adventure)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
  }
end
