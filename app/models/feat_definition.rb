# frozen_string_literal: true

class FeatDefinition < ApplicationRecord
  self.primary_key = "id"

  has_many :sheet_feats, foreign_key: :feat_id, dependent: :destroy
  has_many :adventure_sheet_feats, foreign_key: :feat_id, dependent: :destroy

  validates :id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :category, presence: true, inclusion: { in: %w[combat general metamagic item_creation] }

  scope :by_category, ->(cat) { where(category: cat) }
  scope :repeatable,  -> { where(repeatable: true) }

  # Feats that require a choice (weapon, skill, or school)
  scope :parameterised, -> { where.not(choice_type: nil) }

  # Frontend expects camelCase keys to match the FeatDefinition TS interface
  def as_json(options = {})
    {
      id: id,
      name: name,
      category: category,
      prerequisites: prerequisites,
      effects: effects,
      repeatable: repeatable,
      choiceType: choice_type,
      summary: summary
    }
  end
end
