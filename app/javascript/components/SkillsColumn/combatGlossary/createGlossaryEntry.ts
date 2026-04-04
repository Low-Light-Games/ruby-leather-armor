import type { CombatGlossaryEntry } from './types';

export function createGlossaryEntry(title: string, ...paragraphs: string[]): CombatGlossaryEntry {
  return { title, paragraphs };
}
