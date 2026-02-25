# frozen_string_literal: true

class AdventureSheet < ApplicationRecord
  belongs_to :adventure
  belongs_to :sheet, optional: true # reference to the original player sheet (nullable)

  has_many :adventure_sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :adventure_sheet_feats
  has_many :adventure_sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :adventure_sheet_spells

  validates :name, presence: true
  validates :strength, :intelligence, :dexterity, :constitution, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }
  validates :gold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Recompute derived stats after any save. Called explicitly after feat/spell
  # sync operations as well.
  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end
end
