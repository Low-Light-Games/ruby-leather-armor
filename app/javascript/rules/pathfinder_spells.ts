/**
 * Pathfinder 1e Core Rulebook — Spell aggregator.
 * Re-exports all spell data and provides lookup helpers.
 */

import { SpellDefinition, SpellSchool } from './pathfinder_spells_types';
import { ABJURATION_SPELLS } from './pathfinder_spells_abjuration';
import { CONJURATION_SPELLS } from './pathfinder_spells_conjuration';
import { DIVINATION_SPELLS } from './pathfinder_spells_divination';
import { ENCHANTMENT_SPELLS } from './pathfinder_spells_enchantment';
import { EVOCATION_SPELLS } from './pathfinder_spells_evocation';
import { ILLUSION_SPELLS } from './pathfinder_spells_illusion';
import { NECROMANCY_SPELLS } from './pathfinder_spells_necromancy';
import { TRANSMUTATION_SPELLS } from './pathfinder_spells_transmutation';
import { UNIVERSAL_SPELLS } from './pathfinder_spells_universal';

export type { SpellDefinition, SpellSchool } from './pathfinder_spells_types';
export type { SpellComponent, SpellEffect } from './pathfinder_spells_types';

// ─── Combined array ──────────────────────────────────────────

/** All Core Rulebook level 0–1 spells in one flat array. */
export const ALL_SPELLS: SpellDefinition[] = [
  ...ABJURATION_SPELLS,
  ...CONJURATION_SPELLS,
  ...DIVINATION_SPELLS,
  ...ENCHANTMENT_SPELLS,
  ...EVOCATION_SPELLS,
  ...ILLUSION_SPELLS,
  ...NECROMANCY_SPELLS,
  ...TRANSMUTATION_SPELLS,
  ...UNIVERSAL_SPELLS,
];

// ─── Lookup helpers ──────────────────────────────────────────

/** Find a spell by its unique id. */
export function getSpellById(id: string): SpellDefinition | undefined {
  return ALL_SPELLS.find(s => s.id === id);
}

/** Get all spells of a given school. */
export function getSpellsBySchool(school: SpellSchool): SpellDefinition[] {
  return ALL_SPELLS.filter(s => s.school === school);
}

/** Get all spells available to a given class at a specific level. */
export function getSpellsByClassAndLevel(className: string, level: number): SpellDefinition[] {
  const key = className.toLowerCase();
  return ALL_SPELLS.filter(s => s.classLevels[key] === level);
}

/** Get all cantrips (level 0) for a given class. */
export function getCantrips(className: string): SpellDefinition[] {
  return getSpellsByClassAndLevel(className, 0);
}

/** Get all level-1 spells for a given class. */
export function getLevel1Spells(className: string): SpellDefinition[] {
  return getSpellsByClassAndLevel(className, 1);
}

/**
 * Get all spells available to a class up to (and including) a given max level.
 * Useful for showing a character's full spell list.
 */
export function getSpellsForClass(className: string, maxLevel: number = 1): SpellDefinition[] {
  const key = className.toLowerCase();
  return ALL_SPELLS.filter(s => {
    const lvl = s.classLevels[key];
    return lvl !== undefined && lvl <= maxLevel;
  });
}
