# frozen_string_literal: true

class StoryClue < ApplicationRecord
  belongs_to :story
  belongs_to :adventure, optional: true
  belongs_to :location, class_name: "StoryLocation", optional: true
  belongs_to :npc, class_name: "StoryNpc", optional: true

  SOURCES           = %w[manual enricher embellisher].freeze
  DISCOVERY_METHODS = %w[social exploration magic combat automatic].freeze
  DIFFICULTIES      = %w[automatic easy moderate hard].freeze

  validates :title, presence: true
  validates :description, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :discovery_method, inclusion: { in: DISCOVERY_METHODS }
  validates :difficulty, inclusion: { in: DIFFICULTIES }

  scope :for_adventure, ->(adventure) {
    where(story_id: adventure.story_id, adventure_id: [nil, adventure.id])
  }

  scope :story_level, -> { where(adventure_id: nil) }
end
