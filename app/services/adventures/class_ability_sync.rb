# frozen_string_literal: true

module Adventures
  # Links {AdventureSheet} rows to {ClassAbilityDefinition} records for the
  # sheet's Pathfinder class and level (used by buff resolution, prompts, UI).
  module ClassAbilitySync
    MIN_LEVEL_BY_ID = {
      "greater_rage" => 11,
      "mighty_rage" => 20,
    }.freeze

    module_function

    def sync!(adventure_sheet)
      slug = adventure_sheet.character_class.to_s.strip.downcase
      return adventure_sheet if slug.blank?

      level = adventure_sheet.level.to_i
      ClassAbilityDefinition.where(pf1e_class: slug).find_each do |defn|
        min = MIN_LEVEL_BY_ID[defn.id] || 1
        next if level < min

        adventure_sheet.adventure_sheet_class_abilities.find_or_create_by!(class_ability_id: defn.id)
      end

      adventure_sheet
    end
  end
end
