# frozen_string_literal: true

# Sole writer: Lore::ApplyNpcs (single-writer invariant per
# docs/design_philosophy.md §18).
class AdventureNpc < ApplicationRecord
  ATTITUDES = %w[helpful friendly indifferent unfriendly hostile].freeze
  SOURCES   = %w[seed runtime].freeze

  belongs_to :adventure
  belongs_to :story_npc, optional: true
  belongs_to :adventure_actor_sheet, optional: true, foreign_key: :actor_sheet_id
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
  scope :hostile,       -> { where(attitude: %w[unfriendly hostile]) }
  scope :non_hostile,   -> { where.not(attitude: %w[unfriendly hostile]) }
  scope :with_sheet,    -> { where.not(actor_sheet_id: nil) }
  scope :nearest_for, ->(adventure, embedding, limit:) {
    for_adventure(adventure)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
  }
end
