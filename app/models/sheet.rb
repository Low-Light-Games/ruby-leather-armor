# frozen_string_literal: true

class Sheet < ApplicationRecord
  belongs_to :user

  has_many :adventure_sheets, dependent: :nullify
  has_many :sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :sheet_feats
  has_many :sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :sheet_spells
  has_many :sheet_items, dependent: :destroy
  has_many :item_definitions, through: :sheet_items

  validates :name, presence: true
  validates :strength, presence: true
  validates :intelligence, presence: true
  validates :dexterity, presence: true
  validates :constitution, presence: true
  validates :wisdom, presence: true
  validates :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  validate :skill_ranks_within_pathfinder_rules

  include SheetCurrency

  # Recompute derived stats after any save. Called explicitly after feat/spell
  # sync operations as well.
  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end

  private

  def skill_ranks_within_pathfinder_rules
    return unless self.class.column_names.include?("skill_ranks")

    CharacterStats::SkillRanksValidator.errors_for(self).each do |msg|
      errors.add(:skill_ranks, msg)
    end
  end
end
