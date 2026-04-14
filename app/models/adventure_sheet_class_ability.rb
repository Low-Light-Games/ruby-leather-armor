# frozen_string_literal: true

class AdventureSheetClassAbility < ApplicationRecord
  belongs_to :adventure_sheet
  belongs_to :class_ability_definition

  validates :class_ability_definition_id, uniqueness: { scope: :adventure_sheet_id }
end
