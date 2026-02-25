/**
 * Pathfinder 1e Core Rulebook — Necromancy Spells (Level 0–1).
 * All content is Open Game Content — mechanical rules only.
 */

import { SpellDefinition } from './pathfinder_spells_types';

export const NECROMANCY_SPELLS: SpellDefinition[] = [
  // ─── Level 0 ───────────────────────────────────────────────

  {
    id: 'bleed',
    name: 'Bleed',
    school: 'necromancy',
    classLevels: { cleric: 0, sorcerer: 0, wizard: 0 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'close',
    duration: 'instantaneous',
    savingThrow: 'Will negates',
    spellResistance: true,
    effects: [
      { type: 'special', description: 'Cause a dying creature (at negative HP) to resume losing 1 HP per round. Only works on living creatures currently at negative HP and stable.' },
    ],
    summary: 'Cause a stable dying creature to resume losing HP.',
  },
  {
    id: 'disrupt_undead',
    name: 'Disrupt Undead',
    school: 'necromancy',
    classLevels: { sorcerer: 0, wizard: 0 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'close',
    duration: 'instantaneous',
    savingThrow: 'none',
    spellResistance: true,
    effects: [
      { type: 'damage', dice: '1d6', damageType: 'positive energy' },
    ],
    summary: 'Ranged touch deals 1d6 damage to one undead.',
  },
  {
    id: 'stabilize',
    name: 'Stabilize',
    school: 'necromancy',
    classLevels: { cleric: 0, druid: 0 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'close',
    duration: 'instantaneous',
    savingThrow: 'Will negates (harmless)',
    spellResistance: true,
    effects: [
      { type: 'healing', dice: '0', bonusPerLevel: 0, maxBonus: 0 },
      { type: 'special', description: 'Target dying creature (at negative HP) becomes stable.' },
    ],
    summary: 'Stabilize a dying creature (does not restore HP).',
  },
  {
    id: 'touch_of_fatigue',
    name: 'Touch of Fatigue',
    school: 'necromancy',
    classLevels: { sorcerer: 0, wizard: 0 },
    components: ['V', 'S', 'M'],
    castingTime: '1 standard action',
    range: 'touch',
    duration: '1 round/level',
    savingThrow: 'Fortitude negates',
    spellResistance: true,
    effects: [
      { type: 'condition', condition: 'fatigued' },
    ],
    summary: 'Touch fatigues target (Fort negates). No effect on already fatigued creatures.',
  },

  // ─── Level 1 ───────────────────────────────────────────────

  {
    id: 'cause_fear',
    name: 'Cause Fear',
    school: 'necromancy',
    descriptors: ['fear', 'mind-affecting'],
    classLevels: { bard: 1, cleric: 1, sorcerer: 1, wizard: 1 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'close',
    duration: '1d4 rounds or 1 round (see text)',
    savingThrow: 'Will partial',
    spellResistance: true,
    effects: [
      { type: 'condition', condition: 'frightened (1d4 rounds, or shaken 1 round on save)', hitDiceLimit: 5 },
    ],
    summary: 'One creature of 5 HD or less becomes frightened (Will: shaken 1 round).',
  },
  {
    id: 'chill_touch',
    name: 'Chill Touch',
    school: 'necromancy',
    classLevels: { sorcerer: 1, wizard: 1 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'touch',
    duration: 'instantaneous',
    savingThrow: 'Fortitude partial or Will negates (see text)',
    spellResistance: true,
    effects: [
      { type: 'damage', dice: '1d6', damageType: 'negative energy' },
      { type: 'ability_modifier', ability: 'strength', bonus: -1 },
      { type: 'special', description: 'One touch per level. Each touch deals 1d6 negative energy and 1 STR damage (Fort negates STR damage). Against undead: no damage but target flees for 1d4+CL rounds (Will negates).' },
    ],
    summary: 'Touch deals 1d6 + 1 STR damage per touch (1 touch/level).',
  },
  {
    id: 'inflict_light_wounds',
    name: 'Inflict Light Wounds',
    school: 'necromancy',
    classLevels: { cleric: 1 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'touch',
    duration: 'instantaneous',
    savingThrow: 'Will half',
    spellResistance: true,
    effects: [
      { type: 'damage', dice: '1d8', damageType: 'negative energy', perCasterLevel: true, maxDice: 1 },
      { type: 'special', description: 'Deals 1d8 + 1/level (max +5) negative energy damage. Heals undead for same amount.' },
    ],
    summary: 'Touch deals 1d8 + 1/level (max +5) negative energy. Heals undead.',
  },
  {
    id: 'ray_of_enfeeblement',
    name: 'Ray of Enfeeblement',
    school: 'necromancy',
    classLevels: { sorcerer: 1, wizard: 1 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'close',
    duration: '1 round/level',
    savingThrow: 'Fortitude half',
    spellResistance: true,
    effects: [
      { type: 'ability_modifier', ability: 'strength', bonus: -6 },
      { type: 'special', description: 'Ranged touch attack imposes 1d6+1 per 2 CL (max 1d6+5) STR penalty. Fort halves. Cannot reduce below 1.' },
    ],
    summary: 'Ray imposes 1d6+1 per 2 CL (max +5) STR penalty. Fort halves.',
  },
  {
    id: 'ray_of_sickening',
    name: 'Ray of Sickening',
    school: 'necromancy',
    classLevels: { sorcerer: 1, wizard: 1 },
    components: ['V', 'S', 'M'],
    castingTime: '1 standard action',
    range: 'close',
    duration: '1 round/level',
    savingThrow: 'Fortitude partial (1 round)',
    spellResistance: true,
    effects: [
      { type: 'condition', condition: 'sickened' },
    ],
    summary: 'Ray sickens target for 1 round/level. Fort: sickened 1 round only.',
  },
];
