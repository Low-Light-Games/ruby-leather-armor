/**
 * Pathfinder 1e Core Rulebook — Illusion Spells (Level 0–1).
 * All content is Open Game Content — mechanical rules only.
 */

import { SpellDefinition } from './pathfinder_spells_types';

export const ILLUSION_SPELLS: SpellDefinition[] = [
  // ─── Level 0 ───────────────────────────────────────────────

  {
    id: 'ghost_sound',
    name: 'Ghost Sound',
    school: 'illusion',
    subschool: 'figment',
    classLevels: { bard: 0, sorcerer: 0, wizard: 0 },
    components: ['V', 'S', 'M'],
    castingTime: '1 standard action',
    range: 'close',
    duration: '1 round/level',
    savingThrow: 'Will disbelief',
    spellResistance: false,
    effects: [
      { type: 'utility', description: 'Create illusory sounds (up to 4 normal humans per CL). Volume ranges from whisper to loud shouting.' },
    ],
    summary: 'Create illusory sounds. Volume scales with caster level.',
  },

  // ─── Level 1 ───────────────────────────────────────────────

  {
    id: 'color_spray',
    name: 'Color Spray',
    school: 'illusion',
    subschool: 'pattern',
    descriptors: ['mind-affecting'],
    classLevels: { sorcerer: 1, wizard: 1 },
    components: ['V', 'S', 'M'],
    castingTime: '1 standard action',
    range: 'close',
    duration: 'instantaneous (see text)',
    savingThrow: 'Will negates',
    spellResistance: true,
    effects: [
      { type: 'special', description: '15-ft cone. Creatures affected based on HD: 2 HD or less = unconscious/blinded/stunned 2d4 rounds then blinded/stunned 1d4 rounds then stunned 1 round; 3-4 HD = blinded/stunned 1d4 rounds then stunned 1 round; 5+ HD = stunned 1 round.' },
    ],
    summary: '15-ft cone: creatures stunned/blinded/unconscious based on HD.',
  },
  {
    id: 'disguise_self',
    name: 'Disguise Self',
    school: 'illusion',
    subschool: 'glamer',
    classLevels: { bard: 1, sorcerer: 1, wizard: 1 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'personal',
    duration: '10 min/level',
    savingThrow: 'none (interact: Will disbelief)',
    spellResistance: false,
    effects: [
      { type: 'skill_bonus', skill: 'Disguise', bonus: 10 },
      { type: 'utility', description: 'Change appearance including clothing, armor, weapons, equipment. Can appear up to 1 ft shorter/taller and thin/fat/average.' },
    ],
    summary: '+10 Disguise. Change appearance (height ±1 ft, build, equipment).',
  },
  {
    id: 'magic_aura',
    name: 'Magic Aura',
    school: 'illusion',
    subschool: 'glamer',
    classLevels: { bard: 1, sorcerer: 1, wizard: 1 },
    components: ['V', 'S', 'F'],
    castingTime: '1 standard action',
    range: 'touch',
    duration: '1 day/level',
    savingThrow: 'none (see text)',
    spellResistance: false,
    effects: [
      { type: 'utility', description: 'Alter an object to radiate a false magic aura (or no aura) to detection spells. One object up to 5 lbs/level.' },
    ],
    summary: 'Make an object radiate a false magical aura (or suppress its aura).',
  },
  {
    id: 'silent_image',
    name: 'Silent Image',
    school: 'illusion',
    subschool: 'figment',
    classLevels: { bard: 1, sorcerer: 1, wizard: 1 },
    components: ['V', 'S', 'F'],
    castingTime: '1 standard action',
    range: 'long',
    duration: 'concentration',
    savingThrow: 'Will disbelief (if interacted with)',
    spellResistance: false,
    effects: [
      { type: 'utility', description: 'Create a visual illusion of an object, creature, or force up to 4 10-ft cubes + 1 per CL. No sound, smell, texture, or temperature. Concentration to move/animate.' },
    ],
    summary: 'Create a purely visual illusion (no sound). Concentration to maintain.',
  },
  {
    id: 'vanish',
    name: 'Vanish',
    school: 'illusion',
    subschool: 'glamer',
    classLevels: { bard: 1, sorcerer: 1, wizard: 1 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'touch',
    duration: '1 round/level (max 5 rounds)',
    savingThrow: 'Will negates (harmless)',
    spellResistance: true,
    effects: [
      { type: 'condition', condition: 'invisible (as invisibility spell, ends on attack)' },
    ],
    summary: 'Subject turns invisible for 1 round/level (max 5). Ends on attack.',
  },
  {
    id: 'ventriloquism',
    name: 'Ventriloquism',
    school: 'illusion',
    subschool: 'figment',
    classLevels: { bard: 1, sorcerer: 1, wizard: 1 },
    components: ['V', 'F'],
    castingTime: '1 standard action',
    range: 'close',
    duration: '1 min/level',
    savingThrow: 'Will disbelief',
    spellResistance: false,
    effects: [
      { type: 'utility', description: 'Make your voice (or any sound you can make) seem to come from any point within range. You can speak in any language you know.' },
    ],
    summary: 'Project your voice to any location within range.',
  },
];
