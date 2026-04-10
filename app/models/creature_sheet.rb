# frozen_string_literal: true

class CreatureSheet < ApplicationRecord
  belongs_to :adventure

  has_many :creature_sheet_feats, dependent: :destroy
  has_many :feat_definitions, through: :creature_sheet_feats
  has_many :creature_sheet_items, dependent: :destroy
  has_many :item_definitions, through: :creature_sheet_items
  has_many :creature_sheet_spells, dependent: :destroy
  has_many :spell_definitions, through: :creature_sheet_spells

  CREATURE_TYPES = %w[npc monster beast animal].freeze
  ATTITUDES = %w[hostile unfriendly indifferent friendly helpful].freeze
  ORIGINS = %w[bestiary ai template unknown].freeze

  validates :name, presence: true
  validates :creature_type, presence: true, inclusion: { in: CREATURE_TYPES }
  validates :attitude, inclusion: { in: ATTITUDES }, allow_nil: true
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true
  validates :strength, :dexterity, :constitution, :intelligence, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  include SheetCurrency

  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end

end
