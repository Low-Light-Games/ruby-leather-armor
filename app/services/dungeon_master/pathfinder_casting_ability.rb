# frozen_string_literal: true

module DungeonMaster
  # Maps Pathfinder 1e class slug (lowercase) to the ability that governs spell DCs
  # for that class's spell list.
  module PathfinderCastingAbility
    CLASS_TO_CASTING_ABILITY = {
      "wizard" => :intelligence,
      "sorcerer" => :charisma,
      "cleric" => :wisdom,
      "druid" => :wisdom,
      "bard" => :charisma,
      "paladin" => :charisma,
      "ranger" => :wisdom,
      "witch" => :intelligence,
      "oracle" => :charisma,
      "summoner" => :charisma,
      "magus" => :intelligence,
      "inquisitor" => :wisdom,
      "alchemist" => :intelligence,
      "warpriest" => :wisdom,
      "shaman" => :wisdom,
      "bloodrager" => :charisma,
      "antipaladin" => :charisma,
      "investigator" => :intelligence
    }.freeze

    module_function

    # @param character_class [String] e.g. "Wizard", "fighter/wizard"
    # @return [Symbol, nil]
    def primary_for_class(character_class)
      return nil if character_class.blank?

      slug = character_class.to_s.downcase.split(%r{[/\s]+}).find { |s| CLASS_TO_CASTING_ABILITY.key?(s) }
      CLASS_TO_CASTING_ABILITY[slug] if slug
    end
  end
end
