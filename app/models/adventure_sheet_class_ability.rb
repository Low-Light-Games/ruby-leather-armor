# frozen_string_literal: true

class AdventureSheetClassAbility < ApplicationRecord
  belongs_to :adventure_sheet
  belongs_to :class_ability_definition, foreign_key: :class_ability_id, inverse_of: :adventure_sheet_class_abilities

  validates :class_ability_id, uniqueness: { scope: :adventure_sheet_id }
end
