# frozen_string_literal: true

class EncounterTableEntry < ApplicationRecord
  belongs_to :encounter_table

  ENTRY_TYPES = %w[fixed ai_prompt].freeze

  validates :title, presence: true
  validates :description, presence: true
  validates :entry_type, presence: true, inclusion: { in: ENTRY_TYPES }
  validates :weight, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def fixed?
    entry_type == "fixed"
  end

  def ai_prompt?
    entry_type == "ai_prompt"
  end

  def matches_terrain?(terrain)
    return true if terrain_types.blank?
    terrain_types.split(",").map(&:strip).include?(terrain.to_s)
  end

  def matches_level?(level)
    return true if min_party_level.nil? && max_party_level.nil?
    return level >= min_party_level if max_party_level.nil?
    return level <= max_party_level if min_party_level.nil?
    level.between?(min_party_level, max_party_level)
  end

  def has_manifest?
    creature_manifest.is_a?(Array) && creature_manifest.any?
  end
end
