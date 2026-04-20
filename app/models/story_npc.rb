# frozen_string_literal: true

class StoryNpc < ApplicationRecord
  belongs_to :story
  belongs_to :adventure, optional: true
  belongs_to :location, class_name: "StoryLocation", optional: true

  has_many :story_clues, foreign_key: :npc_id, dependent: :nullify

  SOURCES   = %w[manual enricher embellisher].freeze
  ROLES     = %w[quest_giver informant antagonist bystander merchant].freeze
  ATTITUDES = %w[friendly indifferent unfriendly].freeze

  validates :name, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :role, inclusion: { in: ROLES }
  validates :attitude, inclusion: { in: ATTITUDES }

  scope :for_adventure, ->(adventure) {
    where(story_id: adventure.story_id, adventure_id: [nil, adventure.id])
  }

  scope :story_level, -> { where(adventure_id: nil) }
  scope :manual_source, -> { where(source: "manual") }
end
