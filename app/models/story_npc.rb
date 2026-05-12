# frozen_string_literal: true

class StoryNpc < ApplicationRecord
  belongs_to :story
  belongs_to :adventure, optional: true
  belongs_to :location, class_name: "StoryLocation", optional: true
  belongs_to :bestiary_entry, optional: true

  accepts_nested_attributes_for :bestiary_entry, update_only: true

  SOURCES   = %w[manual].freeze
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
  scope :for_story, ->(story) { where(story_id: story.id) }
  scope :ordered_by_id, -> { order(:id) }
  scope :manual_source, -> { where(source: "manual") }
end
