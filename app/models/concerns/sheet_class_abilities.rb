# frozen_string_literal: true

# Live class-ability list from {ClassAbilityDefinition} for the sheet's
# character_class and level — no persisted pivot rows.
module SheetClassAbilities
  extend ActiveSupport::Concern

  def class_ability_definitions
    ClassAbilityDefinition.applicable_for_character_sheet(self)
  end
end
