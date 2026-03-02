# frozen_string_literal: true

class EncounterTable < ApplicationRecord
  belongs_to :story, optional: true

  has_many :encounter_table_entries, dependent: :destroy
  accepts_nested_attributes_for :encounter_table_entries, allow_destroy: true

  validates :name, presence: true
  validates :check_frequency_hours, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :encounter_chance, presence: true,
            numericality: { only_integer: true, in: 0..100 }

  scope :global_default, -> { where(story_id: nil) }
  scope :for_story, ->(story_id) { where(story_id: story_id) }

  def self.table_for(story)
    for_story(story.id).first || global_default.first
  end

  def roll_encounter(terrain: nil, party_level: nil)
    return nil if rand(100) >= encounter_chance

    eligible = encounter_table_entries
    eligible = eligible.select { |e| e.matches_terrain?(terrain) } if terrain.present?
    eligible = eligible.select { |e| e.matches_level?(party_level) } if party_level.present?
    return nil if eligible.empty?

    weighted_pick(eligible)
  end

  private

  def weighted_pick(entries)
    total = entries.sum(&:weight)
    roll  = rand(total)
    entries.each do |entry|
      roll -= entry.weight
      return entry if roll < 0
    end
    entries.last
  end
end
