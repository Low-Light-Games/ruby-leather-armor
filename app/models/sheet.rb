# frozen_string_literal: true

class Sheet < ApplicationRecord
  STARTER_KEYS = Onboarding::PrebuiltCharacters::ALL.keys.freeze

  belongs_to :user

  has_many :adventure_sheets, dependent: :nullify
  has_many :sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :sheet_feats
  has_many :sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :sheet_spells
  has_many :sheet_items, dependent: :destroy
  has_many :item_definitions, through: :sheet_items

  enum :source_kind, { custom: "custom", starter: "starter" }, default: "custom"

  validates :name, presence: true
  validates :strength, presence: true
  validates :intelligence, presence: true
  validates :dexterity, presence: true
  validates :constitution, presence: true
  validates :wisdom, presence: true
  validates :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }
  validates :starter_key, inclusion: { in: STARTER_KEYS }, allow_nil: true
  validates :starter_key, presence: true, if: :starter?
  validates :starter_key, absence: true, if: :custom?

  validate :skill_ranks_within_pathfinder_rules

  before_validation :normalize_starter_key

  include SheetCurrency

  # Recompute derived stats after any save. Called explicitly after feat/spell
  # sync operations as well.
  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end

  private

  def normalize_starter_key
    self.starter_key = starter_key.presence
  end

  def skill_ranks_within_pathfinder_rules
    return unless self.class.column_names.include?("skill_ranks")

    CharacterStats::SkillRanksValidator.errors_for(self).each do |msg|
      errors.add(:skill_ranks, msg)
    end
  end
end
