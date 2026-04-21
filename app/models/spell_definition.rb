# frozen_string_literal: true

class SpellDefinition < ApplicationRecord
  self.primary_key = "id"

  has_many :sheet_spells, foreign_key: :spell_id, dependent: :destroy
  has_many :adventure_sheet_spells, foreign_key: :spell_id, dependent: :destroy

  validates :id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :school, presence: true

  scope :by_school, ->(school) { where(school: school) }
  scope :named_case_insensitive, ->(name) { where("LOWER(name) = ?", name.to_s.downcase) }

  # Spells available to a given class (checks JSONB class_levels key existence)
  scope :for_class, ->(class_id) {
    where("class_levels ? :cls", cls: class_id)
  }

  # Spells available to a class at or below a given spell level
  scope :for_class_and_max_level, ->(class_id, max_level) {
    where("(class_levels->>:cls)::int <= :lvl", cls: class_id, lvl: max_level)
  }

  def self.find_by_name_case_insensitive(name)
    named_case_insensitive(name).first
  end

  # Frontend expects camelCase keys to match the SpellDefinition TS interface
  def as_json(options = {})
    {
      id: id,
      name: name,
      school: school,
      subschool: subschool,
      descriptors: descriptors,
      classLevels: class_levels,
      components: components,
      materialComponent: material_component,
      castingTime: casting_time,
      range: range,
      duration: duration,
      savingThrow: saving_throw,
      spellResistance: spell_resistance,
      effects: effects,
      summary: summary
    }
  end
end
