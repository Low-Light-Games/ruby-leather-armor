# frozen_string_literal: true

class AdventureActorSheet < ApplicationRecord
  belongs_to :adventure

  has_many :adventure_actor_sheet_feats,
           dependent: :destroy,
           foreign_key: :actor_sheet_id,
           inverse_of: :adventure_actor_sheet
  has_many :feat_definitions, through: :adventure_actor_sheet_feats
  has_many :adventure_actor_sheet_items,
           dependent: :destroy,
           foreign_key: :actor_sheet_id,
           inverse_of: :adventure_actor_sheet
  has_many :item_definitions, through: :adventure_actor_sheet_items
  has_many :adventure_actor_sheet_spells,
           dependent: :destroy,
           foreign_key: :actor_sheet_id,
           inverse_of: :adventure_actor_sheet
  has_many :spell_definitions, through: :adventure_actor_sheet_spells

  CREATURE_TYPES = %w[npc monster beast animal].freeze
  ATTITUDES = %w[hostile unfriendly indifferent friendly helpful].freeze
  ORIGINS = %w[bestiary ai template unknown].freeze
  ELIMINATED_CONDITIONS = %w[dead fled surrendered].freeze

  validates :name, presence: true
  validates :creature_type, presence: true, inclusion: { in: CREATURE_TYPES }
  validates :attitude, inclusion: { in: ATTITUDES }, allow_nil: true
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true
  validates :strength, :dexterity, :constitution, :intelligence, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }

  include SheetCurrency

  scope :ai_generated, -> { where(origin: "ai") }
  scope :alphabetical, -> { order(:name) }
  scope :alive, lambda {
    where("hp > 0")
      .where("NOT (conditions ?| array[:keys])", keys: ELIMINATED_CONDITIONS)
  }

  def self.unique_id_for_name(name)
    relation = where(name: name.to_s)
    relation.one? ? relation.first.id : nil
  end

  def recompute_derived_stats!
    stats = CharacterStats::Calculator.new(self).compute
    update_column(:derived_stats, stats)
  end

end
