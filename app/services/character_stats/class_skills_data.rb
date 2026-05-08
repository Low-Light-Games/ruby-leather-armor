# frozen_string_literal: true

module CharacterStats
  class ClassSkillsData
    LISTS = {
      "barbarian" => [
        "Acrobatics", "Climb", "Craft", "Handle Animal", "Intimidate", "Knowledge (Nature)",
        "Perception", "Ride", "Survival", "Swim",
      ].freeze,
      "bard" => [
        "Acrobatics", "Appraise", "Bluff", "Climb", "Craft", "Diplomacy", "Disguise", "Escape Artist",
        "Intimidate", "Knowledge (Arcana)", "Knowledge (Dungeoneering)", "Knowledge (Engineering)",
        "Knowledge (Geography)", "Knowledge (History)", "Knowledge (Local)", "Knowledge (Nature)",
        "Knowledge (Nobility)", "Knowledge (Planes)", "Knowledge (Religion)", "Linguistics",
        "Perception", "Perform", "Profession", "Sense Motive", "Sleight of Hand", "Spellcraft",
        "Stealth", "Use Magic Device",
      ].freeze,
      "cleric" => [
        "Appraise", "Craft", "Diplomacy", "Heal", "Knowledge (Arcana)", "Knowledge (History)",
        "Knowledge (Nobility)", "Knowledge (Planes)", "Knowledge (Religion)", "Linguistics",
        "Profession", "Sense Motive", "Spellcraft",
      ].freeze,
      "druid" => [
        "Climb", "Craft", "Fly", "Handle Animal", "Heal", "Knowledge (Geography)", "Knowledge (Nature)",
        "Perception", "Profession", "Ride", "Spellcraft", "Survival", "Swim",
      ].freeze,
      "fighter" => [
        "Climb", "Craft", "Handle Animal", "Intimidate", "Knowledge (Dungeoneering)",
        "Knowledge (Engineering)", "Profession", "Ride", "Survival", "Swim",
      ].freeze,
      "monk" => [
        "Acrobatics", "Climb", "Craft", "Escape Artist", "Intimidate", "Knowledge (History)",
        "Knowledge (Religion)", "Perception", "Perform", "Profession", "Ride", "Stealth", "Swim",
      ].freeze,
      "paladin" => [
        "Craft", "Diplomacy", "Handle Animal", "Heal", "Knowledge (Nobility)", "Knowledge (Religion)",
        "Profession", "Ride", "Sense Motive", "Spellcraft",
      ].freeze,
      "ranger" => [
        "Climb", "Craft", "Handle Animal", "Heal", "Intimidate", "Knowledge (Dungeoneering)",
        "Knowledge (Geography)", "Knowledge (Nature)", "Perception", "Profession", "Ride", "Spellcraft",
        "Stealth", "Survival", "Swim",
      ].freeze,
      "rogue" => [
        "Acrobatics", "Appraise", "Bluff", "Climb", "Craft", "Diplomacy", "Disable Device", "Disguise",
        "Escape Artist", "Intimidate", "Knowledge (Dungeoneering)", "Knowledge (Local)", "Linguistics",
        "Perception", "Perform", "Profession", "Sense Motive", "Sleight of Hand", "Stealth", "Swim",
        "Use Magic Device",
      ].freeze,
      "sorcerer" => [
        "Appraise", "Bluff", "Craft", "Fly", "Intimidate", "Knowledge (Arcana)", "Profession",
        "Spellcraft", "Use Magic Device",
      ].freeze,
      "wizard" => [
        "Appraise", "Craft", "Fly", "Knowledge (Arcana)", "Knowledge (Dungeoneering)",
        "Knowledge (Engineering)", "Knowledge (Geography)", "Knowledge (History)", "Knowledge (Local)",
        "Knowledge (Nature)", "Knowledge (Nobility)", "Knowledge (Planes)", "Knowledge (Religion)",
        "Linguistics", "Profession", "Spellcraft",
      ].freeze,
    }.freeze
  end
end
