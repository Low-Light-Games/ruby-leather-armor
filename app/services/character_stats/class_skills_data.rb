# frozen_string_literal: true

module CharacterStats
  # Pathfinder 1e class skill lists (Core Rulebook / SRD). Keys match Calculator skill names.
  #
  # Client mirror (keep identical): app/javascript/rules/pathfinder_class_skills.ts (`CLASS_SKILLS_BY_ID`).
  class ClassSkillsData
    LISTS = {
      "barbarian" => [
        "Acrobatics", "Climb", "Craft", "Handle Animal", "Intimidate", "Knowledge (nature)",
        "Perception", "Ride", "Survival", "Swim",
      ].freeze,
      "bard" => [
        "Acrobatics", "Appraise", "Bluff", "Climb", "Craft", "Diplomacy", "Disguise", "Escape Artist",
        "Intimidate", "Knowledge (arcana)", "Knowledge (dungeoneering)", "Knowledge (engineering)",
        "Knowledge (geography)", "Knowledge (history)", "Knowledge (local)", "Knowledge (nature)",
        "Knowledge (nobility)", "Knowledge (planes)", "Knowledge (religion)", "Linguistics",
        "Perception", "Perform", "Profession", "Sense Motive", "Sleight of Hand", "Spellcraft",
        "Stealth", "Use Magic Device",
      ].freeze,
      "cleric" => [
        "Appraise", "Craft", "Diplomacy", "Heal", "Knowledge (arcana)", "Knowledge (history)",
        "Knowledge (nobility)", "Knowledge (planes)", "Knowledge (religion)", "Linguistics",
        "Profession", "Sense Motive", "Spellcraft",
      ].freeze,
      "druid" => [
        "Climb", "Craft", "Fly", "Handle Animal", "Heal", "Knowledge (geography)", "Knowledge (nature)",
        "Perception", "Profession", "Ride", "Spellcraft", "Survival", "Swim",
      ].freeze,
      "fighter" => [
        "Climb", "Craft", "Handle Animal", "Intimidate", "Knowledge (dungeoneering)",
        "Knowledge (engineering)", "Profession", "Ride", "Survival", "Swim",
      ].freeze,
      "monk" => [
        "Acrobatics", "Climb", "Craft", "Escape Artist", "Intimidate", "Knowledge (history)",
        "Knowledge (religion)", "Perception", "Perform", "Profession", "Ride", "Stealth", "Swim",
      ].freeze,
      "paladin" => [
        "Craft", "Diplomacy", "Handle Animal", "Heal", "Knowledge (nobility)", "Knowledge (religion)",
        "Profession", "Ride", "Sense Motive", "Spellcraft",
      ].freeze,
      "ranger" => [
        "Climb", "Craft", "Handle Animal", "Heal", "Intimidate", "Knowledge (dungeoneering)",
        "Knowledge (geography)", "Knowledge (nature)", "Perception", "Profession", "Ride", "Spellcraft",
        "Stealth", "Survival", "Swim",
      ].freeze,
      "rogue" => [
        "Acrobatics", "Appraise", "Bluff", "Climb", "Craft", "Diplomacy", "Disable Device", "Disguise",
        "Escape Artist", "Intimidate", "Knowledge (dungeoneering)", "Knowledge (local)", "Linguistics",
        "Perception", "Perform", "Profession", "Sense Motive", "Sleight of Hand", "Stealth", "Swim",
        "Use Magic Device",
      ].freeze,
      "sorcerer" => [
        "Appraise", "Bluff", "Craft", "Fly", "Intimidate", "Knowledge (arcana)", "Profession",
        "Spellcraft", "Use Magic Device",
      ].freeze,
      "wizard" => [
        "Appraise", "Craft", "Fly", "Knowledge (arcana)", "Knowledge (dungeoneering)",
        "Knowledge (engineering)", "Knowledge (geography)", "Knowledge (history)", "Knowledge (local)",
        "Knowledge (nature)", "Knowledge (nobility)", "Knowledge (planes)", "Knowledge (religion)",
        "Linguistics", "Profession", "Spellcraft",
      ].freeze,
    }.freeze
  end
end
