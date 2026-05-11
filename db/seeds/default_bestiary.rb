# frozen_string_literal: true

# Default-by-type BestiaryEntry rows.
#
# These are the cast-resolver's deterministic fallback when a creature name
# the AI emits doesn't match an existing AdventureNpc, an existing
# CreatureSheet, or any named BestiaryEntry. Stat blocks are calibrated
# for a CR-3 baseline and varied per role per the type enum the cast
# resolver picks from.
#
# Idempotent on default_for_type — re-running db:seed is safe.

DEFAULT_BESTIARY_ENTRIES ||= [
  {
    id: "default_beast", name: "Default Beast",
    default_for_type: "beast",
    source: "Internal — cast resolver fallback",
    cr: 3, creature_type: "animal", alignment: "N", size: "Medium",
    strength: 16, dexterity: 14, constitution: 14, intelligence: 2, wisdom: 12, charisma: 6,
    hp_formula: "3d8+9", ac: 14, base_attack: 3, speed: 40,
    special_abilities: [{ "name" => "Natural Attack", "damage" => "1d6+3" }],
    feats: ["Skill Focus (Perception)"],
    skills: { "Perception" => 6, "Stealth" => 4 },
    description: "Generic four-legged predator. Used when the cast resolver hands us a beast it cannot pin to a named bestiary entry."
  },
  {
    id: "default_fighter", name: "Default Fighter",
    default_for_type: "fighter",
    source: "Internal — cast resolver fallback",
    cr: 3, creature_type: "humanoid", alignment: "N", size: "Medium",
    strength: 16, dexterity: 13, constitution: 14, intelligence: 10, wisdom: 11, charisma: 9,
    hp_formula: "3d10+9", ac: 17, base_attack: 3, speed: 30,
    special_abilities: [],
    feats: ["Power Attack", "Weapon Focus (longsword)"],
    skills: { "Intimidate" => 5, "Perception" => 4 },
    description: "Generic armed combatant. Full BAB, medium armor, single weapon attack."
  },
  {
    id: "default_goblinoid", name: "Default Goblinoid",
    default_for_type: "goblinoid",
    source: "Internal — cast resolver fallback",
    cr: 2, creature_type: "humanoid", alignment: "NE", size: "Medium",
    strength: 13, dexterity: 14, constitution: 12, intelligence: 8, wisdom: 10, charisma: 7,
    hp_formula: "2d10+4", ac: 15, base_attack: 2, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }],
    feats: ["Improved Initiative"],
    skills: { "Perception" => 3, "Stealth" => 5 },
    description: "Generic small-or-medium humanoid raider. Used for crowds the AI labels as goblinoid (orcs, goblins, hobgoblins, kobolds, gnolls — anything not pinned to a specific bestiary row)."
  },
  {
    id: "default_spellcaster", name: "Default Spellcaster",
    default_for_type: "spellcaster",
    source: "Internal — cast resolver fallback",
    cr: 3, creature_type: "humanoid", alignment: "N", size: "Medium",
    strength: 9, dexterity: 13, constitution: 12, intelligence: 16, wisdom: 12, charisma: 13,
    hp_formula: "3d6+3", ac: 12, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Spell-like Attack", "damage" => "1d6", "type" => "force" }],
    feats: ["Combat Casting", "Spell Focus (evocation)"],
    skills: { "Knowledge (arcana)" => 9, "Spellcraft" => 9, "Concentration" => 7 },
    description: "Generic arcane caster. Low HP, low AC, single ranged attack spell. Decent Will save baseline."
  },
  {
    id: "default_commoner", name: "Default Commoner",
    default_for_type: "commoner",
    source: "Internal — cast resolver fallback",
    cr: 1, creature_type: "humanoid", alignment: "N", size: "Medium",
    strength: 11, dexterity: 10, constitution: 11, intelligence: 10, wisdom: 11, charisma: 10,
    hp_formula: "1d6+1", ac: 10, base_attack: 0, speed: 30,
    special_abilities: [],
    feats: [],
    skills: { "Perception" => 2, "Profession" => 4 },
    description: "Generic non-combatant villager. Used when the cast resolver names someone the world implies but the author never statted (a passing farmer, an unnamed merchant)."
  },
].freeze

puts "Seeding #{DEFAULT_BESTIARY_ENTRIES.size} default-by-type bestiary entries..."

DEFAULT_BESTIARY_ENTRIES.each do |attrs|
  BestiaryEntry.find_or_create_by!(default_for_type: attrs[:default_for_type]) do |entry|
    attrs.each { |k, v| entry.send("#{k}=", v) unless k == :default_for_type }
  end
end

puts "Done. #{BestiaryEntry.where.not(default_for_type: nil).count} default-by-type entries total."
