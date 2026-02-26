# frozen_string_literal: true

class ItemDefinition < ApplicationRecord
  self.primary_key = "id"

  ITEM_TYPES = %w[armor shield weapon gear potion wondrous ammunition].freeze
  SLOTS = %w[armor shield head headband eyes shoulders neck chest body belt wrists hands ring feet none].freeze

  has_many :sheet_items, foreign_key: :item_definition_id, dependent: :destroy
  has_many :adventure_sheet_items, foreign_key: :item_definition_id, dependent: :destroy

  validates :id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :item_type, presence: true, inclusion: { in: ITEM_TYPES }
  validates :slot, presence: true, inclusion: { in: SLOTS }
  validates :weight, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_gp, numericality: { greater_than_or_equal_to: 0 }
  validates :armor_bonus, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :shield_bonus, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :arcane_spell_failure, numericality: { only_integer: true, in: 0..100 }
  validates :armor_check_penalty, numericality: { only_integer: true, less_than_or_equal_to: 0 }

  scope :by_type, ->(type) { where(item_type: type) }
  scope :by_slot, ->(slot) { where(slot: slot) }
  scope :armor_and_shields, -> { where(item_type: %w[armor shield]) }

  # Frontend expects camelCase keys to match the TS ItemDefinition interface
  def as_json(options = {})
    {
      id: id,
      name: name,
      itemType: item_type,
      category: category,
      slot: slot,
      weight: weight.to_f,
      costGp: cost_gp.to_f,
      armorBonus: armor_bonus,
      shieldBonus: shield_bonus,
      maxDexBonus: max_dex_bonus,
      armorCheckPenalty: armor_check_penalty,
      arcaneSpellFailure: arcane_spell_failure,
      speed30: speed_30,
      speed20: speed_20,
      weaponCategory: weapon_category,
      weaponType: weapon_type,
      damageDice: damage_dice,
      criticalRange: critical_range,
      damageType: damage_type,
      rangeIncrement: range_increment,
      properties: properties,
      effects: effects,
      summary: summary,
    }
  end
end
