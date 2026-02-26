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

  validates :name, presence: true
  validates :strength, :intelligence, :dexterity, :constitution, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  # ── Currency helpers ─────────────────────────────────────────
  # The DB column `currency` is a JSONB hash:
  #   { "gold" => 0, "silver" => 0, "copper" => 0, "platinum" => 0 }

  CURRENCY_KEYS = %w[gold silver copper platinum].freeze

  def total_coins
    return 0 unless currency.is_a?(Hash)
    currency.values_at(*CURRENCY_KEYS).compact.sum(&:to_i)
  end

  # Total value expressed in gold pieces (for cost comparison)
  def total_gp_value
    return 0.0 unless currency.is_a?(Hash)
    pp = (currency["platinum"] || 0).to_f * 10
    gp = (currency["gold"]     || 0).to_f
    sp = (currency["silver"]   || 0).to_f / 10
    cp = (currency["copper"]   || 0).to_f / 100
    pp + gp + sp + cp
  end

  # Recompute derived stats after any save. Called explicitly after feat/spell
  # sync operations as well.
  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end
end
