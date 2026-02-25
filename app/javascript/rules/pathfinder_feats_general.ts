/**
 * Pathfinder 1e Core Rulebook — General, Metamagic & Item Creation Feats.
 * All content is Open Game Content — mechanical rules only.
 */

import { FeatDefinition } from './pathfinder_feats_types';

// ─── General Feats ───────────────────────────────────────────

export const GENERAL_FEATS: FeatDefinition[] = [
  {
    id: 'acrobatic',
    name: 'Acrobatic',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Acrobatics', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Fly', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Acrobatics and Fly (+4 at 10+ ranks each).',
  },
  {
    id: 'acrobatic_steps',
    name: 'Acrobatic Steps',
    category: 'general',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 15 },
      { type: 'feat', feat: 'nimble_moves' },
    ],
    effects: [
      { type: 'movement', description: 'Move through up to 15 ft of difficult terrain per round as if it were normal terrain.' },
    ],
    repeatable: false,
    summary: 'Ignore up to 15 ft of difficult terrain per round.',
  },
  {
    id: 'alertness',
    name: 'Alertness',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Perception', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Sense Motive', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Perception and Sense Motive (+4 at 10+ ranks each).',
  },
  {
    id: 'animal_affinity',
    name: 'Animal Affinity',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Handle Animal', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Ride', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Handle Animal and Ride (+4 at 10+ ranks each).',
  },
  {
    id: 'armor_proficiency_light',
    name: 'Armor Proficiency (Light)',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'proficiency', category: 'light armor' },
    ],
    repeatable: false,
    summary: 'No armor check penalty on attack rolls while wearing light armor.',
  },
  {
    id: 'armor_proficiency_medium',
    name: 'Armor Proficiency (Medium)',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'armor_proficiency_light' },
    ],
    effects: [
      { type: 'proficiency', category: 'medium armor' },
    ],
    repeatable: false,
    summary: 'No armor check penalty on attack rolls while wearing medium armor.',
  },
  {
    id: 'armor_proficiency_heavy',
    name: 'Armor Proficiency (Heavy)',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'armor_proficiency_medium' },
    ],
    effects: [
      { type: 'proficiency', category: 'heavy armor' },
    ],
    repeatable: false,
    summary: 'No armor check penalty on attack rolls while wearing heavy armor.',
  },
  {
    id: 'athletic',
    name: 'Athletic',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Climb', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Swim', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Climb and Swim (+4 at 10+ ranks each).',
  },
  {
    id: 'augment_summoning',
    name: 'Augment Summoning',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'spell_focus_conjuration' },
    ],
    effects: [
      { type: 'summoning_bonus', stat: 'strength', bonus: 4 },
      { type: 'summoning_bonus', stat: 'constitution', bonus: 4 },
    ],
    repeatable: false,
    summary: 'Summoned creatures gain +4 STR and +4 CON.',
  },
  {
    id: 'combat_casting',
    name: 'Combat Casting',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'concentration', bonus: 4, condition: 'when casting defensively or grappled' },
    ],
    repeatable: false,
    summary: '+4 to concentration checks for casting defensively or while grappled.',
  },
  {
    id: 'deceitful',
    name: 'Deceitful',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Bluff', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Disguise', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Bluff and Disguise (+4 at 10+ ranks each).',
  },
  {
    id: 'deft_hands',
    name: 'Deft Hands',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Disable Device', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Sleight of Hand', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Disable Device and Sleight of Hand (+4 at 10+ ranks each).',
  },
  {
    id: 'diehard',
    name: 'Diehard',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'endurance' },
    ],
    effects: [
      { type: 'special', description: 'Automatically stabilize when reduced to negative HP. Can choose to act while at negative HP (staggered), taking 1 HP damage per round of activity.' },
    ],
    repeatable: false,
    summary: 'Auto-stabilize at negative HP. Can act while disabled (staggered).',
  },
  {
    id: 'endurance',
    name: 'Endurance',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'fort_save', bonus: 4, condition: 'vs hot/cold environments, suffocation, or forced march' },
      { type: 'special', description: 'May sleep in light or medium armor without becoming fatigued.' },
    ],
    repeatable: false,
    summary: '+4 on checks to avoid nonlethal from environment. Sleep in medium armor.',
  },
  {
    id: 'eschew_materials',
    name: 'Eschew Materials',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'special', description: 'Cast any spell with a material component costing 1 gp or less without needing that component.' },
    ],
    repeatable: false,
    summary: 'Cast spells without material components worth 1 gp or less.',
  },
  {
    id: 'extra_channel',
    name: 'Extra Channel',
    category: 'general',
    prerequisites: [
      { type: 'class_feature', feature: 'channel energy' },
    ],
    effects: [
      { type: 'extra_resource', resource: 'channel energy', amount: 2 },
    ],
    repeatable: true,
    summary: 'Channel energy 2 additional times per day.',
  },
  {
    id: 'fleet',
    name: 'Fleet',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'speed', bonus: 5, condition: 'when wearing light or no armor' },
    ],
    repeatable: true,
    summary: '+5 ft base speed (light or no armor). Can be taken multiple times.',
  },
  {
    id: 'great_fortitude',
    name: 'Great Fortitude',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'fort_save', bonus: 2 },
    ],
    repeatable: false,
    summary: '+2 to Fortitude saves.',
  },
  {
    id: 'improved_great_fortitude',
    name: 'Improved Great Fortitude',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'great_fortitude' },
    ],
    effects: [
      { type: 'reroll', target: 'Fortitude save', usesPerDay: 1 },
    ],
    repeatable: false,
    summary: 'Reroll one Fortitude save per day. Must take second result.',
  },
  {
    id: 'improved_iron_will',
    name: 'Improved Iron Will',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'iron_will' },
    ],
    effects: [
      { type: 'reroll', target: 'Will save', usesPerDay: 1 },
    ],
    repeatable: false,
    summary: 'Reroll one Will save per day. Must take second result.',
  },
  {
    id: 'improved_lightning_reflexes',
    name: 'Improved Lightning Reflexes',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'lightning_reflexes' },
    ],
    effects: [
      { type: 'reroll', target: 'Reflex save', usesPerDay: 1 },
    ],
    repeatable: false,
    summary: 'Reroll one Reflex save per day. Must take second result.',
  },
  {
    id: 'iron_will',
    name: 'Iron Will',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'will_save', bonus: 2 },
    ],
    repeatable: false,
    summary: '+2 to Will saves.',
  },
  {
    id: 'leadership',
    name: 'Leadership',
    category: 'general',
    prerequisites: [
      { type: 'character_level', minimum: 7 },
    ],
    effects: [
      { type: 'special', description: 'Gain a cohort (level = yours - 2) and followers based on Leadership score (character level + CHA modifier + modifiers).' },
    ],
    repeatable: false,
    summary: 'Attract a cohort and followers based on Leadership score.',
  },
  {
    id: 'lightning_reflexes',
    name: 'Lightning Reflexes',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'ref_save', bonus: 2 },
    ],
    repeatable: false,
    summary: '+2 to Reflex saves.',
  },
  {
    id: 'magical_aptitude',
    name: 'Magical Aptitude',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Spellcraft', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Use Magic Device', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Spellcraft and Use Magic Device (+4 at 10+ ranks each).',
  },
  {
    id: 'martial_weapon_proficiency',
    name: 'Martial Weapon Proficiency',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'proficiency', category: 'one martial weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: 'Gain proficiency with one martial weapon.',
  },
  {
    id: 'natural_spell',
    name: 'Natural Spell',
    category: 'general',
    prerequisites: [
      { type: 'ability', ability: 'wisdom', minimum: 13 },
      { type: 'class_feature', feature: 'wild shape' },
    ],
    effects: [
      { type: 'special', description: 'Cast spells while in wild shape form. Substitute various material components with equivalents of the form.' },
    ],
    repeatable: false,
    summary: 'Cast spells while using wild shape.',
  },
  {
    id: 'nimble_moves',
    name: 'Nimble Moves',
    category: 'general',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
    ],
    effects: [
      { type: 'movement', description: 'Move through 5 ft of difficult terrain per round as if it were normal terrain.' },
    ],
    repeatable: false,
    summary: 'Ignore 5 ft of difficult terrain per round.',
  },
  {
    id: 'persuasive',
    name: 'Persuasive',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Diplomacy', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Intimidate', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Diplomacy and Intimidate (+4 at 10+ ranks each).',
  },
  {
    id: 'run',
    name: 'Run',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'movement', description: 'Run at 5x speed (instead of 4x). +4 to Acrobatics checks for running jumps. Retain DEX bonus to AC while running.' },
    ],
    repeatable: false,
    summary: 'Run at 5x speed. +4 running jumps. Keep DEX bonus to AC while running.',
  },
  {
    id: 'self_sufficient',
    name: 'Self-Sufficient',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Heal', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Survival', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Heal and Survival (+4 at 10+ ranks each).',
  },
  {
    id: 'shield_proficiency',
    name: 'Shield Proficiency',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'proficiency', category: 'shields (except tower)' },
    ],
    repeatable: false,
    summary: 'No armor check penalty on attack rolls while using a shield.',
  },
  {
    id: 'simple_weapon_proficiency',
    name: 'Simple Weapon Proficiency',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'proficiency', category: 'all simple weapons' },
    ],
    repeatable: false,
    summary: 'Gain proficiency with all simple weapons.',
  },
  {
    id: 'skill_focus',
    name: 'Skill Focus',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'chosen skill', bonus: 3, when10Ranks: 6 },
    ],
    repeatable: true,
    choiceType: 'skill',
    summary: '+3 to chosen skill (+6 at 10+ ranks).',
  },
  {
    id: 'spell_focus',
    name: 'Spell Focus',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'spell_dc_bonus', bonus: 1, school: 'chosen school' },
    ],
    repeatable: true,
    choiceType: 'school',
    summary: '+1 to save DCs of spells from chosen school.',
  },
  {
    id: 'spell_focus_conjuration',
    name: 'Spell Focus (Conjuration)',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'spell_dc_bonus', bonus: 1, school: 'conjuration' },
    ],
    repeatable: false,
    summary: '+1 to save DCs of conjuration spells. (Specific instance for Augment Summoning prerequisite.)',
  },
  {
    id: 'greater_spell_focus',
    name: 'Greater Spell Focus',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'spell_focus' },
    ],
    effects: [
      { type: 'spell_dc_bonus', bonus: 1, school: 'chosen school' },
    ],
    repeatable: true,
    choiceType: 'school',
    summary: '+1 additional to save DCs of spells from chosen school (stacks with Spell Focus).',
  },
  {
    id: 'spell_penetration',
    name: 'Spell Penetration',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'sr_check', bonus: 2 },
    ],
    repeatable: false,
    summary: '+2 on caster level checks to overcome spell resistance.',
  },
  {
    id: 'greater_spell_penetration',
    name: 'Greater Spell Penetration',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'spell_penetration' },
    ],
    effects: [
      { type: 'bonus', target: 'sr_check', bonus: 2 },
    ],
    repeatable: false,
    summary: '+2 additional on caster level checks to overcome SR (stacks with Spell Penetration).',
  },
  {
    id: 'stealthy',
    name: 'Stealthy',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'skill_bonus', skill: 'Escape Artist', bonus: 2, when10Ranks: 4 },
      { type: 'skill_bonus', skill: 'Stealth', bonus: 2, when10Ranks: 4 },
    ],
    repeatable: false,
    summary: '+2 Escape Artist and Stealth (+4 at 10+ ranks each).',
  },
  {
    id: 'toughness',
    name: 'Toughness',
    category: 'general',
    prerequisites: [],
    effects: [
      { type: 'hp_bonus', perLevel: 1, minimum: 3 },
    ],
    repeatable: false,
    summary: '+1 HP per level (minimum +3 HP).',
  },
  {
    id: 'tower_shield_proficiency',
    name: 'Tower Shield Proficiency',
    category: 'general',
    prerequisites: [
      { type: 'feat', feat: 'shield_proficiency' },
    ],
    effects: [
      { type: 'proficiency', category: 'tower shield' },
    ],
    repeatable: false,
    summary: 'No armor check penalty on attack rolls while using a tower shield.',
  },
  {
    id: 'turn_undead',
    name: 'Turn Undead',
    category: 'general',
    prerequisites: [
      { type: 'class_feature', feature: 'channel positive energy' },
    ],
    effects: [
      { type: 'special', description: 'Channel positive energy to cause undead to flee (as the panicked condition) for 1 minute. Will save (DC 10 + 1/2 cleric level + CHA mod) negates.' },
    ],
    repeatable: false,
    summary: 'Channel positive energy to make undead flee (Will negates).',
  },
];

// ─── Metamagic Feats ─────────────────────────────────────────

export const METAMAGIC_FEATS: FeatDefinition[] = [
  {
    id: 'empower_spell',
    name: 'Empower Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 2, effect: 'All variable numeric effects of the spell are increased by half (+50%).' },
    ],
    repeatable: false,
    summary: '+2 spell level: increase variable numeric effects by 50%.',
  },
  {
    id: 'enlarge_spell',
    name: 'Enlarge Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 1, effect: 'Double the range of the spell.' },
    ],
    repeatable: false,
    summary: '+1 spell level: double the range.',
  },
  {
    id: 'extend_spell',
    name: 'Extend Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 1, effect: 'Double the duration of the spell.' },
    ],
    repeatable: false,
    summary: '+1 spell level: double the duration.',
  },
  {
    id: 'heighten_spell',
    name: 'Heighten Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 0, effect: 'Cast the spell at a higher spell level. All level-dependent variables (including save DC) use the heightened level. Level increase is variable (chosen at casting).' },
    ],
    repeatable: false,
    summary: 'Cast spell at a higher level. Save DCs and effects use the new level.',
  },
  {
    id: 'maximize_spell',
    name: 'Maximize Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 3, effect: 'All variable numeric effects of the spell are maximized.' },
    ],
    repeatable: false,
    summary: '+3 spell level: maximize all variable numeric effects.',
  },
  {
    id: 'quicken_spell',
    name: 'Quicken Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 4, effect: 'Cast the spell as a swift action instead of its normal casting time.' },
    ],
    repeatable: false,
    summary: '+4 spell level: cast as a swift action.',
  },
  {
    id: 'silent_spell',
    name: 'Silent Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 1, effect: 'Cast the spell without verbal components.' },
    ],
    repeatable: false,
    summary: '+1 spell level: remove verbal component.',
  },
  {
    id: 'still_spell',
    name: 'Still Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 1, effect: 'Cast the spell without somatic components.' },
    ],
    repeatable: false,
    summary: '+1 spell level: remove somatic component.',
  },
  {
    id: 'widen_spell',
    name: 'Widen Spell',
    category: 'metamagic',
    prerequisites: [],
    effects: [
      { type: 'metamagic', levelIncrease: 3, effect: 'Double the area of a burst, emanation, line, or spread spell.' },
    ],
    repeatable: false,
    summary: '+3 spell level: double the area.',
  },
];

// ─── Item Creation Feats ─────────────────────────────────────

export const ITEM_CREATION_FEATS: FeatDefinition[] = [
  {
    id: 'brew_potion',
    name: 'Brew Potion',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 3 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'potions (up to 3rd-level spells)', casterLevelRequired: 3 },
    ],
    repeatable: false,
    summary: 'Create potions of any spell of 3rd level or lower that targets a creature.',
  },
  {
    id: 'craft_magic_arms_and_armor',
    name: 'Craft Magic Arms and Armor',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 5 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'magic weapons, armor, and shields', casterLevelRequired: 5 },
    ],
    repeatable: false,
    summary: 'Create magic weapons, armor, and shields.',
  },
  {
    id: 'craft_rod',
    name: 'Craft Rod',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 9 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'magic rods', casterLevelRequired: 9 },
    ],
    repeatable: false,
    summary: 'Create magic rods.',
  },
  {
    id: 'craft_staff',
    name: 'Craft Staff',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 11 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'magic staves', casterLevelRequired: 11 },
    ],
    repeatable: false,
    summary: 'Create magic staves.',
  },
  {
    id: 'craft_wand',
    name: 'Craft Wand',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 5 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'wands (up to 4th-level spells)', casterLevelRequired: 5 },
    ],
    repeatable: false,
    summary: 'Create wands of any spell of 4th level or lower.',
  },
  {
    id: 'craft_wondrous_item',
    name: 'Craft Wondrous Item',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 3 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'wondrous items', casterLevelRequired: 3 },
    ],
    repeatable: false,
    summary: 'Create miscellaneous wondrous items.',
  },
  {
    id: 'forge_ring',
    name: 'Forge Ring',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 7 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'magic rings', casterLevelRequired: 7 },
    ],
    repeatable: false,
    summary: 'Create magic rings.',
  },
  {
    id: 'scribe_scroll',
    name: 'Scribe Scroll',
    category: 'item_creation',
    prerequisites: [
      { type: 'caster_level', minimum: 1 },
    ],
    effects: [
      { type: 'item_creation', itemType: 'scrolls', casterLevelRequired: 1 },
    ],
    repeatable: false,
    summary: 'Create scrolls of any spell you know or have prepared.',
  },
];
