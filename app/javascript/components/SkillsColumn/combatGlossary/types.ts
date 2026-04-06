/**
 * Glossary keys for combat stat help — one key per help entry.
 */

export type CombatGlossaryKey =
  | 'ac'
  | 'touchAc'
  | 'flatFooted'
  | 'bab'
  | 'initiative'
  | 'speed'
  | 'cmb'
  | 'cmd'
  | 'fort'
  | 'ref'
  | 'will'
  | 'hpBonus'
  | 'armorBonus'
  | 'shieldBonus'
  | 'acp'
  | 'arcaneSpellFailure'
  | 'encumbrance';

export interface CombatGlossaryEntry {
  title: string;
  paragraphs: string[];
}
