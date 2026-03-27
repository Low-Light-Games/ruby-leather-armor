# frozen_string_literal: true

module Onboarding
  module PrebuiltCharacters
    ROGUE = {
      name: "Maren Ashwick",
      character_class: "Rogue",
      level: 1,
      race: "Human",
      description: "A lean, sharp-eyed woman of no particular origin and fewer allegiances. " \
                   "She learned to pick locks because doors were often between her and eating. " \
                   "She is not brave. She is practical. The dungeon is a place where practical " \
                   "people sometimes find gold, and gold is the only abstraction she trusts.",
      strength: 10,
      dexterity: 17,
      constitution: 12,
      intelligence: 14,
      wisdom: 10,
      charisma: 8,
      currency: { "gold" => 7, "silver" => 0, "copper" => 0, "platinum" => 0 },
      feat_names: ["Weapon Finesse", "Stealthy"],
      item_names: [
        "Leather Armor",
        "Backpack",
        "Thieves' Tools",
        "Rope (Silk/50 ft.)",
        "Torch",
        "Trail Rations (1 Day)",
        "Waterskin",
        "Flint and Steel",
        "Chalk",
        "Short Sword",
        "Shortbow",
        "Dagger",
      ],
    }.freeze

    FIGHTER = {
      name: "Aldric Vane",
      character_class: "Fighter",
      level: 1,
      race: "Human",
      description: "A broad, quiet man who was a soldier until the company disbanded. " \
                   "He is methodical, unhurried, and does not startle easily. He enters " \
                   "dungeons because it is the trade he has left. He sleeps lightly, eats " \
                   "sparingly, and keeps his sword sharp. He does not expect to die old, " \
                   "but he intends to die facing forward.",
      strength: 17,
      dexterity: 13,
      constitution: 14,
      intelligence: 10,
      wisdom: 12,
      charisma: 8,
      currency: { "gold" => 4, "silver" => 0, "copper" => 0, "platinum" => 0 },
      feat_names: ["Power Attack", "Cleave", "Toughness"],
      item_names: [
        "Scale Mail",
        "Heavy Wooden Shield",
        "Backpack",
        "Rope (Silk/50 ft.)",
        "Torch",
        "Trail Rations (1 Day)",
        "Waterskin",
        "Whetstone",
        "Belt Pouch",
        "Longsword",
        "Javelin",
      ],
    }.freeze

    ALL = {
      "rogue"   => ROGUE,
      "fighter" => FIGHTER,
    }.freeze

    def self.find(character_type)
      ALL.fetch(character_type.to_s.downcase) do
        raise ArgumentError, "Unknown character type: #{character_type.inspect}"
      end
    end
  end
end
