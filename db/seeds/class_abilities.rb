# frozen_string_literal: true

# Seed class ability definitions for PF1e beta-combat staples.
# Run: bin/rails runner db/seeds/class_abilities.rb
#   or: bin/rails db:seed (if referenced from seeds.rb)
#
# Production is populated via migrations; this file mirrors catalog effects for dev.
#
# Follow-ups (product): PLACEHOLDER_* round counts mirror the migration seeds — not full PF 1e
# (rage should be Con/class-based; inspire should follow bard level / performance rules).

PLACEHOLDER_RAGE_ROUNDS = { "unit" => "rounds", "fixed" => 10 }.freeze
RAGE_EFFECTS = [
  { "target" => "strength", "bonusType" => "morale", "bonus" => 2 },
  { "target" => "constitution", "bonusType" => "morale", "bonus" => 2 },
  { "target" => "saves", "bonusType" => "morale", "bonus" => 2 },
  { "target" => "ac", "bonusType" => "morale", "bonus" => -2 },
].freeze
GREATER_RAGE_EFFECTS = [
  { "target" => "strength", "bonusType" => "morale", "bonus" => 4 },
  { "target" => "constitution", "bonusType" => "morale", "bonus" => 4 },
  { "target" => "saves", "bonusType" => "morale", "bonus" => 3 },
  { "target" => "ac", "bonusType" => "morale", "bonus" => -2 },
].freeze
MIGHTY_RAGE_EFFECTS = [
  { "target" => "strength", "bonusType" => "morale", "bonus" => 6 },
  { "target" => "constitution", "bonusType" => "morale", "bonus" => 6 },
  { "target" => "saves", "bonusType" => "morale", "bonus" => 4 },
  { "target" => "ac", "bonusType" => "morale", "bonus" => -2 },
].freeze
INSPIRE_COURAGE_EFFECTS = [
  { "target" => "attack", "bonusType" => "competence", "bonus" => 1 },
  { "target" => "damage", "bonusType" => "competence", "bonus" => 1 },
].freeze
PLACEHOLDER_INSPIRE_ROUNDS = { "unit" => "rounds", "fixed" => 100 }.freeze

STAPLES = [
  { id: "rage", name: "Rage", pf1e_class: "barbarian",
    summary: "Enter a powerful battle rage, gaining bonus to Str/Con and Will saves.",
    effects: RAGE_EFFECTS, duration_formula: PLACEHOLDER_RAGE_ROUNDS },
  { id: "greater_rage", name: "Greater Rage", pf1e_class: "barbarian",
    summary: "Enhanced rage with larger bonuses than standard Rage.",
    effects: GREATER_RAGE_EFFECTS, duration_formula: PLACEHOLDER_RAGE_ROUNDS },
  { id: "mighty_rage", name: "Mighty Rage", pf1e_class: "barbarian",
    summary: "Maximum rage bonuses, available at high barbarian levels.",
    effects: MIGHTY_RAGE_EFFECTS, duration_formula: PLACEHOLDER_RAGE_ROUNDS },
  { id: "smite_evil", name: "Smite Evil", pf1e_class: "paladin",
    summary: "Add Cha bonus to attack and level bonus to damage against an evil target." },
  { id: "lay_on_hands", name: "Lay on Hands", pf1e_class: "paladin",
    summary: "Heal hit points with a touch, a number of times per day." },
  { id: "divine_bond", name: "Divine Bond", pf1e_class: "paladin",
    summary: "Form a bond with a mount or weapon, granting it magical enhancements." },
  { id: "channel_energy", name: "Channel Energy", pf1e_class: "cleric",
    summary: "Release a burst of positive or negative energy to heal or harm." },
  { id: "bardic_performance", name: "Bardic Performance", pf1e_class: "bard",
    summary: "Use performance to inspire allies or hinder enemies." },
  { id: "inspire_courage", name: "Inspire Courage", pf1e_class: "bard",
    summary: "Boost attack, damage, and save bonuses for allies via performance.",
    effects: INSPIRE_COURAGE_EFFECTS, duration_formula: PLACEHOLDER_INSPIRE_ROUNDS },
  { id: "wild_shape", name: "Wild Shape", pf1e_class: "druid",
    summary: "Polymorph into an animal or elemental form." },
  { id: "flurry_of_blows", name: "Flurry of Blows", pf1e_class: "monk",
    summary: "Make a full attack with additional unarmed strikes at a penalty." },
  { id: "stunning_fist", name: "Stunning Fist", pf1e_class: "monk",
    summary: "Attempt to stun a target with an unarmed strike." },
  { id: "ki_strike", name: "Ki Strike", pf1e_class: "monk",
    summary: "Unarmed strikes count as magic (and later adamantine/lawful) for DR." },
  { id: "ki_pool", name: "Ki Pool", pf1e_class: "monk",
    summary: "Pool of ki points powering special monk abilities." },
  { id: "evasion", name: "Evasion", pf1e_class: "monk",
    summary: "Take no damage on successful Reflex save against area attacks." },
  { id: "sneak_attack", name: "Sneak Attack", pf1e_class: "rogue",
    summary: "Deal extra dice of damage when flanking or target is denied Dex bonus." },
  { id: "uncanny_dodge", name: "Uncanny Dodge", pf1e_class: "rogue",
    summary: "Retain Dex bonus to AC even when caught flat-footed." },
  { id: "judgment", name: "Judgment", pf1e_class: "inquisitor",
    summary: "Declare a judgment granting bonuses to attack, damage, saves, or AC." },
  { id: "spellstrike", name: "Spellstrike", pf1e_class: "magus",
    summary: "Deliver a touch spell through a melee weapon attack." },
  { id: "spell_combat", name: "Spell Combat", pf1e_class: "magus",
    summary: "Cast a spell and make a full attack in the same round." },
  { id: "arcane_pool", name: "Arcane Pool", pf1e_class: "magus",
    summary: "Pool of arcane points to enhance weapons or power magus abilities." },
  { id: "favored_enemy", name: "Favored Enemy", pf1e_class: "ranger",
    summary: "Gain bonus to attack, damage, and skill checks against chosen creature type." },
  { id: "hunters_bond", name: "Hunter's Bond", pf1e_class: "ranger",
    summary: "Bond with a companion animal or share favored enemy bonuses with allies." },
  { id: "fighting_defensively", name: "Fighting Defensively", pf1e_class: "fighter",
    summary: "Fight defensively to trade offense for AC; use adjudicated_effects when applying as a buff.",
    effects: [], duration_formula: nil },
].freeze

puts "Seeding #{STAPLES.size} class ability definitions..."

STAPLES.each do |attrs|
  ClassAbilityDefinition.find_or_initialize_by(id: attrs[:id]).tap do |ca|
    ca.name = attrs[:name]
    ca.pf1e_class = attrs[:pf1e_class]
    ca.summary = attrs[:summary]
    ca.effects = attrs.fetch(:effects, [])
    ca.duration_formula = attrs.key?(:duration_formula) ? attrs[:duration_formula] : nil
    ca.save!
  end
end

puts "Done — #{ClassAbilityDefinition.count} class ability definitions in the database."
