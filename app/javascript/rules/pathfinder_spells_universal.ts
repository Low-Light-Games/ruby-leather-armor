/**
 * Pathfinder 1e Core Rulebook — Universal Spells (Level 0–1).
 * All content is Open Game Content — mechanical rules only.
 */

import { SpellDefinition } from './pathfinder_spells_types';

export const UNIVERSAL_SPELLS: SpellDefinition[] = [
  // ─── Level 0 ───────────────────────────────────────────────

  {
    id: 'arcane_mark',
    name: 'Arcane Mark',
    school: 'universal',
    classLevels: { sorcerer: 0, wizard: 0 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'touch',
    duration: 'permanent',
    savingThrow: 'none',
    spellResistance: false,
    effects: [
      { type: 'utility', description: 'Inscribes a personal rune or mark (up to 6 characters) on an object or creature (visible or invisible). Detectable by detect magic. An arcane mark on a living creature fades after 1 month.' },
    ],
    summary: 'Inscribe a personal rune on an object or creature.',
  },
  {
    id: 'prestidigitation',
    name: 'Prestidigitation',
    school: 'universal',
    classLevels: { bard: 0, sorcerer: 0, wizard: 0 },
    components: ['V', 'S'],
    castingTime: '1 standard action',
    range: 'close',
    duration: '1 hour',
    savingThrow: 'none (see text)',
    spellResistance: false,
    effects: [
      { type: 'utility', description: 'Minor magical tricks: lift 1 lb, color/clean/soil items in 1 cu ft, chill/warm/flavor 1 lb of material, create small trinkets or illusions (too crude to fool anyone). Once per round. Can maintain up to 3 effects.' },
    ],
    summary: 'Perform minor magical tricks (clean, color, warm, create trinkets, etc.).',
  },

  // No level 1 Universal spells in the Core Rulebook.
];
