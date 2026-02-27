# frozen_string_literal: true

class CreatureSheet < ApplicationRecord
  belongs_to :adventure

  has_many :creature_sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :creature_sheet_feats
  has_many :creature_sheet_items, dependent: :destroy
  has_many :item_definitions, through: :creature_sheet_items
  has_many :creature_sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :creature_sheet_spells

  has_many :encounter_participants, dependent: :nullify

  CREATURE_TYPES = %w[npc monster beast animal].freeze
  ATTITUDES = %w[hostile unfriendly indifferent friendly helpful].freeze

  validates :name, presence: true
  validates :creature_type, presence: true, inclusion: { in: CREATURE_TYPES }
  validates :attitude, inclusion: { in: ATTITUDES }, allow_nil: true
  validates :strength, :dexterity, :constitution, :intelligence, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  CURRENCY_KEYS = %w[gold silver copper platinum].freeze

  def total_coins
    return 0 unless currency.is_a?(Hash)
    currency.values_at(*CURRENCY_KEYS).compact.sum(&:to_i)
  end

  def total_gp_value
    return 0.0 unless currency.is_a?(Hash)
    pp = (currency["platinum"] || 0).to_f * 10
    gp = (currency["gold"]     || 0).to_f
    sp = (currency["silver"]   || 0).to_f / 10
    cp = (currency["copper"]   || 0).to_f / 100
    pp + gp + sp + cp
  end

  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end

  def shift_attitude!(direction, steps: 1)
    return unless attitude
    idx = ATTITUDES.index(attitude)
    return unless idx

    new_idx = if direction == :better
                [idx + steps, ATTITUDES.length - 1].min
              else
                [idx - steps, 0].max
              end

    update!(attitude: ATTITUDES[new_idx])
  end
end
