# frozen_string_literal: true

# Pathfinder 1e OGL/SRD Bestiary seed data.
# All entries are from the Pathfinder Reference Document (Open Game Content).
# Mechanical data only — no copyrighted prose or Golarion-specific lore.

SOURCE_PRD = "Pathfinder Roleplaying Game Reference Document (OGL)"

BESTIARY_ENTRIES = [
  {
    id: "goblin", name: "Goblin", source: SOURCE_PRD,
    cr: 0.33, creature_type: "humanoid", alignment: "NE", size: "Small",
    strength: 11, dexterity: 15, constitution: 12, intelligence: 10, wisdom: 9, charisma: 6,
    hp_formula: "1d10+1", ac: 16, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }],
    feats: ["Improved Initiative"],
    skills: { "Stealth" => 10, "Ride" => 6 },
    environment: "temperate forest and plains"
  },
  {
    id: "skeleton", name: "Skeleton", source: SOURCE_PRD,
    cr: 0.33, creature_type: "undead", alignment: "NE", size: "Medium",
    strength: 15, dexterity: 14, constitution: 0, intelligence: 0, wisdom: 10, charisma: 10,
    hp_formula: "1d8+2", ac: 14, base_attack: 0, speed: 30,
    special_abilities: [{ "name" => "DR", "value" => "5/bludgeoning" }, { "name" => "Darkvision", "range" => 60 }],
    feats: ["Improved Initiative"],
    skills: {},
    environment: "any"
  },
  {
    id: "zombie", name: "Zombie", source: SOURCE_PRD,
    cr: 0.5, creature_type: "undead", alignment: "NE", size: "Medium",
    strength: 17, dexterity: 10, constitution: 0, intelligence: 0, wisdom: 10, charisma: 10,
    hp_formula: "2d8+3", ac: 12, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "DR", "value" => "5/slashing" }, { "name" => "Staggered" }],
    feats: ["Toughness"],
    skills: {},
    environment: "any"
  },
  {
    id: "kobold", name: "Kobold", source: SOURCE_PRD,
    cr: 0.25, creature_type: "humanoid", alignment: "LE", size: "Small",
    strength: 9, dexterity: 13, constitution: 10, intelligence: 10, wisdom: 9, charisma: 8,
    hp_formula: "1d10", ac: 15, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }, { "name" => "Light Sensitivity" }],
    feats: [],
    skills: { "Craft (trapmaking)" => 6, "Perception" => 5 },
    environment: "temperate underground or deep forest"
  },
  {
    id: "orc", name: "Orc", source: SOURCE_PRD,
    cr: 0.33, creature_type: "humanoid", alignment: "CE", size: "Medium",
    strength: 17, dexterity: 11, constitution: 12, intelligence: 7, wisdom: 8, charisma: 6,
    hp_formula: "1d10+1", ac: 13, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }, { "name" => "Light Sensitivity" }, { "name" => "Ferocity" }],
    feats: [],
    skills: { "Intimidate" => 2 },
    environment: "temperate hills, mountains, or underground"
  },
  {
    id: "wolf", name: "Wolf", source: SOURCE_PRD,
    cr: 1, creature_type: "animal", alignment: "N", size: "Medium",
    strength: 13, dexterity: 15, constitution: 15, intelligence: 2, wisdom: 12, charisma: 6,
    hp_formula: "2d8+4", ac: 14, base_attack: 1, speed: 50,
    special_abilities: [{ "name" => "Trip" }],
    feats: ["Skill Focus (Perception)"],
    skills: { "Perception" => 8, "Stealth" => 6, "Survival" => 1 },
    environment: "cold or temperate forests"
  },
  {
    id: "dire_wolf", name: "Dire Wolf", source: SOURCE_PRD,
    cr: 3, creature_type: "animal", alignment: "N", size: "Large",
    strength: 19, dexterity: 15, constitution: 17, intelligence: 2, wisdom: 12, charisma: 10,
    hp_formula: "6d8+18", ac: 14, base_attack: 4, speed: 50,
    special_abilities: [{ "name" => "Trip" }],
    feats: ["Run", "Skill Focus (Perception)", "Weapon Focus (bite)"],
    skills: { "Perception" => 10, "Stealth" => 6, "Survival" => 1 },
    environment: "cold or temperate forests"
  },
  {
    id: "giant_spider", name: "Giant Spider", source: SOURCE_PRD,
    cr: 1, creature_type: "vermin", alignment: "N", size: "Medium",
    strength: 11, dexterity: 17, constitution: 12, intelligence: 0, wisdom: 10, charisma: 2,
    hp_formula: "2d8+2", ac: 14, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Poison", "dc" => 14, "effect" => "1d2 Str" }, { "name" => "Web" }],
    feats: [],
    skills: { "Climb" => 16, "Perception" => 4 },
    environment: "any"
  },
  {
    id: "ogre", name: "Ogre", source: SOURCE_PRD,
    cr: 3, creature_type: "humanoid", alignment: "CE", size: "Large",
    strength: 21, dexterity: 8, constitution: 15, intelligence: 6, wisdom: 10, charisma: 7,
    hp_formula: "4d8+11", ac: 17, base_attack: 3, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }],
    feats: ["Iron Will", "Toughness"],
    skills: { "Climb" => 7, "Perception" => 5 },
    environment: "temperate or cold hills"
  },
  {
    id: "troll", name: "Troll", source: SOURCE_PRD,
    cr: 5, creature_type: "humanoid", alignment: "CE", size: "Large",
    strength: 21, dexterity: 14, constitution: 23, intelligence: 6, wisdom: 9, charisma: 6,
    hp_formula: "6d8+36", ac: 16, base_attack: 4, speed: 30,
    special_abilities: [{ "name" => "Regeneration", "value" => 5, "weakness" => "acid or fire" }, { "name" => "Rend", "damage" => "1d6+7" }],
    feats: ["Intimidating Prowess", "Iron Will", "Skill Focus (Perception)"],
    skills: { "Intimidate" => 9, "Perception" => 8 },
    environment: "cold mountains"
  },
  {
    id: "giant_rat", name: "Giant Rat", source: SOURCE_PRD,
    cr: 0.33, creature_type: "animal", alignment: "N", size: "Small",
    strength: 10, dexterity: 17, constitution: 13, intelligence: 2, wisdom: 13, charisma: 4,
    hp_formula: "1d8+1", ac: 14, base_attack: 0, speed: 40,
    special_abilities: [{ "name" => "Disease", "name_detail" => "Filth Fever" }],
    feats: ["Weapon Finesse"],
    skills: { "Climb" => 11, "Perception" => 4, "Stealth" => 8, "Swim" => 11 },
    environment: "any urban"
  },
  {
    id: "bandit", name: "Bandit", source: SOURCE_PRD,
    cr: 0.5, creature_type: "humanoid", alignment: "NE", size: "Medium",
    strength: 13, dexterity: 11, constitution: 12, intelligence: 10, wisdom: 11, charisma: 10,
    hp_formula: "1d10+1", ac: 15, base_attack: 1, speed: 30,
    special_abilities: [],
    feats: ["Power Attack"],
    skills: { "Intimidate" => 4, "Perception" => 3, "Stealth" => 3 },
    environment: "any land"
  },
  {
    id: "guard", name: "Guard", source: SOURCE_PRD,
    cr: 1, creature_type: "humanoid", alignment: "LN", size: "Medium",
    strength: 14, dexterity: 11, constitution: 13, intelligence: 10, wisdom: 11, charisma: 10,
    hp_formula: "2d10+2", ac: 18, base_attack: 2, speed: 20,
    special_abilities: [],
    feats: ["Alertness", "Weapon Focus (longsword)"],
    skills: { "Intimidate" => 5, "Perception" => 6 },
    environment: "any urban"
  },
  {
    id: "commoner", name: "Commoner", source: SOURCE_PRD,
    cr: 0.5, creature_type: "humanoid", alignment: "N", size: "Medium",
    strength: 11, dexterity: 10, constitution: 11, intelligence: 10, wisdom: 11, charisma: 10,
    hp_formula: "1d6", ac: 10, base_attack: 0, speed: 30,
    special_abilities: [],
    feats: [],
    skills: { "Perception" => 3, "Profession" => 4 },
    environment: "any"
  },
  {
    id: "innkeeper", name: "Innkeeper", source: SOURCE_PRD,
    cr: 1, creature_type: "humanoid", alignment: "N", size: "Medium",
    strength: 10, dexterity: 11, constitution: 11, intelligence: 12, wisdom: 13, charisma: 14,
    hp_formula: "2d8", ac: 10, base_attack: 1, speed: 30,
    special_abilities: [],
    feats: ["Skill Focus (Diplomacy)"],
    skills: { "Diplomacy" => 10, "Profession (innkeeper)" => 8, "Sense Motive" => 6, "Perception" => 5 },
    environment: "any urban"
  },
  {
    id: "bear", name: "Bear (Grizzly)", source: SOURCE_PRD,
    cr: 4, creature_type: "animal", alignment: "N", size: "Large",
    strength: 21, dexterity: 13, constitution: 19, intelligence: 2, wisdom: 12, charisma: 6,
    hp_formula: "5d8+20", ac: 16, base_attack: 3, speed: 40,
    special_abilities: [{ "name" => "Grab" }],
    feats: ["Endurance", "Run", "Skill Focus (Survival)"],
    skills: { "Perception" => 6, "Survival" => 6, "Swim" => 14 },
    environment: "cold forests"
  },
  {
    id: "snake_viper", name: "Venomous Snake", source: SOURCE_PRD,
    cr: 0.5, creature_type: "animal", alignment: "N", size: "Tiny",
    strength: 4, dexterity: 17, constitution: 8, intelligence: 1, wisdom: 13, charisma: 2,
    hp_formula: "1d8-1", ac: 16, base_attack: 0, speed: 20,
    special_abilities: [{ "name" => "Poison", "dc" => 9, "effect" => "1d2 Con" }],
    feats: ["Weapon Finesse"],
    skills: { "Climb" => 11, "Perception" => 9, "Stealth" => 15 },
    environment: "any temperate or warm"
  },
  {
    id: "stirge", name: "Stirge", source: SOURCE_PRD,
    cr: 0.5, creature_type: "magical beast", alignment: "N", size: "Tiny",
    strength: 3, dexterity: 19, constitution: 10, intelligence: 1, wisdom: 12, charisma: 6,
    hp_formula: "1d10", ac: 16, base_attack: 1, speed: 10,
    special_abilities: [{ "name" => "Blood Drain", "damage" => "1 Con" }, { "name" => "Attach" }],
    feats: ["Weapon Finesse"],
    skills: { "Fly" => 8, "Stealth" => 16 },
    environment: "temperate and warm swamps"
  },
  {
    id: "gnoll", name: "Gnoll", source: SOURCE_PRD,
    cr: 1, creature_type: "humanoid", alignment: "CE", size: "Medium",
    strength: 15, dexterity: 10, constitution: 13, intelligence: 8, wisdom: 11, charisma: 8,
    hp_formula: "2d8+2", ac: 15, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }],
    feats: ["Power Attack"],
    skills: { "Perception" => 2 },
    environment: "warm plains"
  },
  {
    id: "hobgoblin", name: "Hobgoblin", source: SOURCE_PRD,
    cr: 0.5, creature_type: "humanoid", alignment: "LE", size: "Medium",
    strength: 13, dexterity: 13, constitution: 12, intelligence: 10, wisdom: 10, charisma: 8,
    hp_formula: "1d10+1", ac: 16, base_attack: 1, speed: 30,
    special_abilities: [{ "name" => "Darkvision", "range" => 60 }],
    feats: ["Toughness"],
    skills: { "Perception" => 2, "Stealth" => 4 },
    environment: "temperate hills"
  },
].freeze

puts "Seeding #{BESTIARY_ENTRIES.size} bestiary entries (OGL/SRD)..."

BESTIARY_ENTRIES.each do |attrs|
  BestiaryEntry.find_or_create_by!(id: attrs[:id]) do |entry|
    attrs.each { |k, v| entry.send("#{k}=", v) unless k == :id }
  end
end

puts "Done. #{BestiaryEntry.count} bestiary entries total."
