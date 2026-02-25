# frozen_string_literal: true

class Sheet < ApplicationRecord
  belongs_to :user

  has_many :adventure_sheets, dependent: :nullify
  has_many :sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :sheet_feats
  has_many :sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :sheet_spells

  validates :name, presence: true
  validates :strength, presence: true
  validates :intelligence, presence: true
  validates :dexterity, presence: true
  validates :constitution, presence: true
  validates :wisdom, presence: true
  validates :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  # Recompute derived stats after any save. Called explicitly after feat/spell
  # sync operations as well.
  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end
end
