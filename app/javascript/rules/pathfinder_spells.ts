/**
 * Pathfinder 1e Core Rulebook — Spell aggregator.
 *
 * Provides lookup / eligibility helpers for spells.
 * The spell definitions are loaded from the API at runtime via
 * GameDataContext, which calls `setSpellDefinitions()`.
 */

import { SpellDefinition, SpellSchool } from './pathfinder_spells_types';
import { getClassById, CastingStyle } from './pathfinder_classes';
import { abilityModifier } from './pathfinder_skills';

export type { CastingStyle } from './pathfinder_classes';
export type { SpellDefinition, SpellSchool } from './pathfinder_spells_types';
export type { SpellComponent, SpellEffect } from './pathfinder_spells_types';

// ─── Module-level cache (populated by GameDataContext) ──────

/** All spell definitions — populated at runtime via setSpellDefinitions(). */
let ALL_SPELLS: SpellDefinition[] = [];

/** Called by GameDataContext after fetching from the API. */
export function setSpellDefinitions(spells: SpellDefinition[]): void {
  ALL_SPELLS = spells;
}

/** Returns the current spell definitions array. */
export function getAllSpells(): SpellDefinition[] {
  return ALL_SPELLS;
}

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

// ─── Spellcasting eligibility ────────────────────────────────

/** Does this class have any spellcasting ability? */
export function isSpellcaster(classId: string | null): boolean {
  if (!classId) return false;
  const cls = getClassById(classId);
  return !!cls?.spellcasting;
}

/**
 * The earliest character level at which this class gains spellcasting.
 * Returns `null` for non-casters.
 */
export function castingStartLevel(classId: string | null): number | null {
  if (!classId) return null;
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return null;

  for (const minLvl of cls.spellcasting.progression) {
    if (minLvl !== null) return minLvl;
  }
  return null;
}

/**
 * Highest spell level a class can access at a given character level.
 * Returns `-1` if the class can't cast anything yet (or isn't a caster).
 */
export function maxSpellLevelForClass(classId: string | null, charLevel: number): number {
  if (!classId) return -1;
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return -1;

  let max = -1;
  for (let spellLvl = 0; spellLvl < cls.spellcasting.progression.length; spellLvl++) {
    const minCharLvl = cls.spellcasting.progression[spellLvl];
    if (minCharLvl !== null && charLevel >= minCharLvl) {
      max = spellLvl;
    }
  }
  return max;
}

// ─── Per-spell eligibility check ─────────────────────────────

export type SpellEligibilityStatus = 'available' | 'too_high_level' | 'wrong_class' | 'no_casting';

export interface SpellEligibility {
  status: SpellEligibilityStatus;
  /** Spell level for the current class (undefined if not on their list). */
  spellLevel: number | undefined;
  /** Human-readable reason when the spell is locked. */
  reason?: string;
}

/**
 * Check whether a character of a given class + level can select a spell.
 *
 * Returns a structured result with status and a user-facing reason if locked.
 */
export function checkSpellEligibility(
  classId: string | null,
  charLevel: number,
  spell: SpellDefinition,
): SpellEligibility {
  if (!classId) {
    // No class → we can't really validate; treat as available so the user
    // can browse freely (matches existing behaviour).
    const lvl = Object.values(spell.classLevels)[0];
    return { status: 'available', spellLevel: lvl };
  }

  const cls = getClassById(classId);
  if (!cls) {
    return { status: 'available', spellLevel: undefined };
  }

  if (!cls.spellcasting) {
    return {
      status: 'no_casting',
      spellLevel: undefined,
      reason: `${cls.name} cannot cast spells`,
    };
  }

  const spellLevel = spell.classLevels[classId.toLowerCase()];
  if (spellLevel === undefined) {
    return {
      status: 'wrong_class',
      spellLevel: undefined,
      reason: `Not on the ${cls.name} spell list`,
    };
  }

  const maxLvl = maxSpellLevelForClass(classId, charLevel);
  if (spellLevel > maxLvl) {
    const minCharLvl = cls.spellcasting.progression[spellLevel];
    return {
      status: 'too_high_level',
      spellLevel,
      reason: minCharLvl !== null
        ? `Requires ${cls.name} level ${minCharLvl} (spell level ${spellLevel})`
        : `Spell level ${spellLevel} not accessible yet`,
    };
  }

  return { status: 'available', spellLevel };
}

/** True when the spell can be picked right now. */
export function canSelectSpell(eligibility: SpellEligibility): boolean {
  return eligibility.status === 'available';
}

// ─── Casting style & spell-slot limits ───────────────────────

/** Determine how a class acquires spells. */
export function getCastingStyle(classId: string | null): CastingStyle {
  if (!classId) return 'none';
  const cls = getClassById(classId);
  return cls?.spellcasting?.style ?? 'none';
}

/**
 * For spontaneous casters: max spells known of a given spell level
 * at a given character level.  Returns 0 if not applicable.
 */
export function maxKnownSpells(
  classId: string | null,
  charLevel: number,
  spellLevel: number,
): number {
  if (!classId) return 0;
  const cls = getClassById(classId);
  const table = cls?.spellcasting?.spellsKnown;
  if (!table) return 0;

  const row = table[Math.min(charLevel, table.length) - 1];
  if (!row) return 0;
  return row[spellLevel] ?? 0;
}

/**
 * For wizard: number of spellbook slots for a given spell level.
 *
 * Cantrips (level 0): all class cantrips go in automatically.
 * Level 1+: starting slots = 3 + INT modifier (at Lv 1),
 *           then +2 per wizard level after 1st (distributed freely
 *           among accessible spell levels; we attribute them all to the
 *           highest accessible level for simplicity until a per-level
 *           tracking UI is added).
 *
 * Returns `Infinity` for cantrips (meaning "all wizard cantrips").
 */
export function wizardSpellbookSlots(
  charLevel: number,
  intScore: number,
  spellLevel: number,
): number {
  if (spellLevel === 0) return Infinity; // cantrips are automatic

  const intMod = abilityModifier(intScore);
  const baseSlots = Math.max(3 + intMod, 1); // at least 1
  const additionalSlots = 2 * Math.max(charLevel - 1, 0);
  return baseSlots + additionalSlots;
}

// ─── Summary helpers for the UI ──────────────────────────────

export interface SpellSlotSummary {
  spellLevel: number;
  label: string;       // "Cantrips" or "1st Level", etc.
  limit: number;       // Infinity for wizard cantrips
  used: number;
  remaining: number;
}

const SPELL_LEVEL_LABELS: Record<number, string> = {
  0: 'Cantrips',
  1: '1st Level',
  2: '2nd Level',
  3: '3rd Level',
  4: '4th Level',
  5: '5th Level',
  6: '6th Level',
  7: '7th Level',
  8: '8th Level',
  9: '9th Level',
};

/**
 * Compute per-spell-level slot summaries for the current character.
 * Only applicable for spontaneous and spellbook casters.
 */
export function computeSpellSlots(
  classId: string | null,
  charLevel: number,
  intScore: number,
  selectedSpellIds: string[],
): SpellSlotSummary[] {
  if (!classId) return [];
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return [];

  const style = cls.spellcasting.style;
  if (style === 'none' || style === 'prepared_list') return [];

  const maxSL = maxSpellLevelForClass(classId, charLevel);
  if (maxSL < 0) return [];

  // Count selected spells per spell level
  const countByLevel: Record<number, number> = {};
  for (const id of selectedSpellIds) {
    const spell = getSpellById(id);
    if (!spell) continue;
    const sl = spell.classLevels[classId.toLowerCase()];
    if (sl !== undefined) {
      countByLevel[sl] = (countByLevel[sl] || 0) + 1;
    }
  }

  const result: SpellSlotSummary[] = [];
  for (let sl = 0; sl <= maxSL; sl++) {
    const used = countByLevel[sl] || 0;

    let limit: number;
    if (style === 'spontaneous') {
      limit = maxKnownSpells(classId, charLevel, sl);
    } else {
      // spellbook
      limit = wizardSpellbookSlots(charLevel, intScore, sl);
    }

    if (limit === 0 && used === 0) continue; // skip unavailable levels

    result.push({
      spellLevel: sl,
      label: SPELL_LEVEL_LABELS[sl] ?? `Level ${sl}`,
      limit,
      used,
      remaining: limit === Infinity ? Infinity : Math.max(limit - used, 0),
    });
  }

  return result;
}

/**
 * Check whether a specific spell can still be added given current slot usage.
 * Works for both spontaneous (known spells) and spellbook (wizard) casters.
 */
export function hasSlotForSpell(
  classId: string | null,
  charLevel: number,
  intScore: number,
  spell: SpellDefinition,
  selectedSpellIds: string[],
): boolean {
  if (!classId) return true; // no class = browse mode, allow anything
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return false;

  const style = cls.spellcasting.style;
  if (style === 'prepared_list') return true; // full-list casters know all
  if (style === 'none') return false;

  const spellLevel = spell.classLevels[classId.toLowerCase()];
  if (spellLevel === undefined) return false;

  // Count how many of this spell level are already selected
  let count = 0;
  for (const id of selectedSpellIds) {
    const s = getSpellById(id);
    if (s && s.classLevels[classId.toLowerCase()] === spellLevel) count++;
  }

  let limit: number;
  if (style === 'spontaneous') {
    limit = maxKnownSpells(classId, charLevel, spellLevel);
  } else {
    limit = wizardSpellbookSlots(charLevel, intScore, spellLevel);
  }

  return count < limit;
}
