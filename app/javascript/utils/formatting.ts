import type { AttributeType } from '../types';

/**
 * Format a numeric modifier with a leading sign: +3, -1, +0.
 * Used across combat stats, skills, saves, rolls, and attribute rows.
 */
export function formatMod(mod: number): string {
  return mod >= 0 ? `+${mod}` : `${mod}`;
}

/** Standard ability abbreviations used in stat displays and roll labels. */
export const ABILITY_ABBR: Record<string, string> = {
  strength: 'STR',
  dexterity: 'DEX',
  constitution: 'CON',
  intelligence: 'INT',
  wisdom: 'WIS',
  charisma: 'CHA',
};

/** Canonical ability score order for iteration. */
export const ATTRIBUTE_ORDER: AttributeType[] = [
  'strength', 'dexterity', 'constitution',
  'intelligence', 'wisdom', 'charisma',
];
