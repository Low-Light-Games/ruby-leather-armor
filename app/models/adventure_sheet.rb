# frozen_string_literal: true

class AdventureSheet < ApplicationRecord
  belongs_to :adventure
  belongs_to :sheet, optional: true # reference to the original player sheet (nullable)

  has_many :adventure_sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :adventure_sheet_feats
  has_many :adventure_sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :adventure_sheet_spells
  has_many :adventure_sheet_items, dependent: :destroy
  has_many :item_definitions, through: :adventure_sheet_items
  has_many :adventure_sheet_class_abilities, dependent: :destroy
  has_many :class_ability_definitions, through: :adventure_sheet_class_abilities

  validates :name, presence: true
  validates :strength, :intelligence, :dexterity, :constitution, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  validate :skill_ranks_within_pathfinder_rules

  include SheetCurrency

  # Primary sheet for prompts / pipeline (eager-loads associations CharacterBlock presenters need).
  def self.for_adventure(adventure)
    adventure.adventure_sheets
      .includes(:feat_definitions, :spell_definitions, :class_ability_definitions,
                adventure_sheet_items: :item_definition)
      .first
  end

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
