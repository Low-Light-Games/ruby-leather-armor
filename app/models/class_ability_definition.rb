# frozen_string_literal: true

# Global catalog row for a Pathfinder 1e class-granted ability (effects, duration, etc.).
class ClassAbilityDefinition < ApplicationRecord
  self.primary_key = :id

  MIN_LEVEL_BY_ID = {
    'greater_rage' => 11,
    'mighty_rage' => 20
  }.freeze

  validates :name,       presence: true
  validates :pf1e_class, presence: true

  # @param sheet [#character_class, #level] e.g. {Sheet}, {AdventureSheet}
  def self.applicable_for_character_sheet(sheet)
    slug = sheet.character_class.to_s.strip.downcase
    return none if slug.blank?

    level = sheet.level.to_i
    base = where(pf1e_class: slug)
    allowed_ids = base.pluck(:id).select { |id| level >= (MIN_LEVEL_BY_ID[id] || 1) }
    where(id: allowed_ids).order(:name)
  end
end
