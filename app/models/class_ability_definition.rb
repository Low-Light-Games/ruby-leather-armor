# frozen_string_literal: true

class ClassAbilityDefinition < ApplicationRecord
  self.primary_key = :id

  has_many :adventure_sheet_class_abilities, foreign_key: :class_ability_id, inverse_of: :class_ability_definition,
                                             dependent: :destroy
  has_many :adventure_sheets, through: :adventure_sheet_class_abilities

  validates :name,       presence: true
  validates :pf1e_class, presence: true
end
