/**
 * Pathfinder 1e Core Rulebook — Feat aggregator.
 *
 * Provides lookup helpers and computation functions for feats.
 * The feat definitions are loaded from the API at runtime via
 * GameDataContext, which calls `setFeatDefinitions()`.
 */

import { AttributeType } from '../types';
import { ABILITY_ABBR } from '../utils/formatting';
import { FeatDefinition, FeatCategory, FeatEffect, Prerequisite } from './pathfinder_feats_types';
import type { BABProgression } from './pathfinder_classes';

export type { FeatDefinition, FeatCategory } from './pathfinder_feats_types';
export type { Prerequisite, FeatEffect, BonusTarget } from './pathfinder_feats_types';

// ─── Module-level cache (populated by GameDataContext) ──────

/** All feat definitions — populated at runtime via setFeatDefinitions(). */
let ALL_FEATS: FeatDefinition[] = [];

/** Called by GameDataContext after fetching from the API. */
export function setFeatDefinitions(feats: FeatDefinition[]): void {
  ALL_FEATS = feats;
}

/** Returns the current feat definitions array. */
export function getAllFeats(): FeatDefinition[] {
  return ALL_FEATS;
}

// ─── Compound Feat ID Helpers ───────────────────────────────

/**
 * Compound feat entries are stored as `"feat_id"` or `"feat_id::choice"`.
 * For example: `"skill_focus::Perception"`, `"weapon_focus::Longsword"`.
 */
export interface ParsedFeatEntry {
  /** The base feat ID (e.g. `"skill_focus"`). */
  featId: string;
  /** The choice (e.g. `"Perception"`) or `null` for non-parameterised feats. */
  choice: string | null;
  /** The original compound string. */
  raw: string;
}

/** Separator used in compound feat IDs. */
export const FEAT_CHOICE_SEPARATOR = '::';

/** Parse a (possibly compound) feat entry string. */
export function parseFeatEntry(entry: string): ParsedFeatEntry {
  const idx = entry.indexOf(FEAT_CHOICE_SEPARATOR);
  if (idx === -1) return { featId: entry, choice: null, raw: entry };
  return {
    featId: entry.substring(0, idx),
    choice: entry.substring(idx + FEAT_CHOICE_SEPARATOR.length),
    raw: entry,
  };
}

/** Build a compound feat entry string. */
export function buildFeatEntry(featId: string, choice: string | null): string {
  return choice ? `${featId}${FEAT_CHOICE_SEPARATOR}${choice}` : featId;
}

/** Lookup a feat by its id (strips compound suffix if present). */
export function getFeatById(id: string): FeatDefinition | undefined {
  const { featId } = parseFeatEntry(id);
  return ALL_FEATS.find(f => f.id === featId);
}

/** Get all feats of a given category. */
export function getFeatsByCategory(category: FeatCategory): FeatDefinition[] {
  return ALL_FEATS.filter(f => f.category === category);
}

/** Get all feats that have no prerequisites (available at level 1 with no prior feats). */
export function getEntryFeats(): FeatDefinition[] {
  return ALL_FEATS.filter(f => f.prerequisites.length === 0);
}

/**
 * Check if a set of feat ids satisfies the feat-chain prerequisites of a target feat.
 * Note: this only checks { type: 'feat' } prerequisites, not ability scores/BAB/etc.
 * Supports compound IDs — `"weapon_focus::Longsword"` satisfies a requirement for `"weapon_focus"`.
 */
export function hasFeatPrerequisites(
  targetFeatId: string,
  ownedFeatIds: Set<string>,
): boolean {
  const feat = getFeatById(targetFeatId);
  if (!feat) return false;
  return feat.prerequisites
    .filter(p => p.type === 'feat')
    .every(p => ownsBaseFeat(ownedFeatIds, (p as { type: 'feat'; feat: string }).feat));
}

// ─── Combat Progression Formulas ─────────────────────────────

/** Compute BAB at a given level for a given BAB progression. */
export function computeBAB(bab: BABProgression, level: number): number {
  switch (bab) {
    case 'full':  return level;
    case '3/4':   return Math.floor(level * 3 / 4);
    case '1/2':   return Math.floor(level / 2);
  }
}

/**
 * Compute base save bonus at a given level.
 *
 * Pathfinder 1e progression:
 *   Good save:  floor(level / 2) + 2
 *   Poor save:  floor((level - 1) / 3)
 */
export function computeBaseSave(good: boolean, level: number): number {
  if (good) return Math.floor(level / 2) + 2;
  return Math.floor((level - 1) / 3);
}

// ─── Prerequisite Checking System ────────────────────────────

/** Character state needed to evaluate feat prerequisites. */
export interface PrerequisiteContext {
  finalAttributes: Record<AttributeType, number>;
  level: number;
  classId: string | null;
  bab: number;
  /** Raw feat entries (may include compound IDs like `"skill_focus::Perception"`). */
  ownedFeatIds: Set<string>;
}

/**
 * Check if `ownedFeatIds` contains a feat matching `requiredId`.
 * Handles compound entries: e.g. `"weapon_focus::Longsword"` matches a requirement for `"weapon_focus"`.
 */
function ownsBaseFeat(ownedFeatIds: Set<string>, requiredId: string): boolean {
  if (ownedFeatIds.has(requiredId)) return true;
  // Check if any compound entry starts with the required feat ID
  for (const entry of ownedFeatIds) {
    const { featId } = parseFeatEntry(entry);
    if (featId === requiredId) return true;
  }
  return false;
}

/** Status of a single prerequisite check. */
export type PrereqStatus = 'met' | 'unmet' | 'unknown';

/** Result of checking one prerequisite. */
export interface PrerequisiteCheck {
  label: string;
  status: PrereqStatus;
}


/** Convert a prerequisite to a human-readable label. */
export function prerequisiteLabel(prereq: Prerequisite): string {
  switch (prereq.type) {
    case 'ability':
      return `${ABILITY_ABBR[prereq.ability] || prereq.ability} ${prereq.minimum}+`;
    case 'bab':
      return `BAB +${prereq.minimum}`;
    case 'feat': {
      const f = getFeatById(prereq.feat);
      return f ? f.name : prereq.feat;
    }
    case 'skill':
      return `${prereq.skill} ${prereq.ranks} ranks`;
    case 'caster_level':
      return `Caster level ${prereq.minimum}`;
    case 'class_ability':
      return prereq.feature;
    case 'class_level': {
      const name = prereq.classId.charAt(0).toUpperCase() + prereq.classId.slice(1);
      return `${name} level ${prereq.level}`;
    }
    case 'character_level':
      return `Character level ${prereq.minimum}`;
    case 'proficiency':
      return `${prereq.weapon} proficiency`;
  }
}

/**
 * Check every prerequisite on a feat against the current character state.
 *
 * Returns an array of { label, status } for each prerequisite.
 * - 'met'     = we can verify the character satisfies it
 * - 'unmet'   = the character definitely does NOT satisfy it
 * - 'unknown' = we can't verify (e.g. skill ranks, caster level) — shown as warning but won't block
 */
export function checkAllPrerequisites(
  feat: FeatDefinition,
  ctx: PrerequisiteContext,
): PrerequisiteCheck[] {
  return feat.prerequisites.map(prereq => {
    const label = prerequisiteLabel(prereq);
    let status: PrereqStatus;

    switch (prereq.type) {
      case 'ability':
        status = ctx.finalAttributes[prereq.ability] >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'bab':
        status = ctx.bab >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'feat':
        status = ownsBaseFeat(ctx.ownedFeatIds, prereq.feat) ? 'met' : 'unmet';
        break;
      case 'character_level':
        status = ctx.level >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'class_level':
        status = (ctx.classId === prereq.classId && ctx.level >= prereq.level) ? 'met' : 'unmet';
        break;
      default:
        // skill, caster_level, class_ability, proficiency — can't fully verify
        status = 'unknown';
    }

    return { label, status };
  });
}

/** Returns true if the character meets all hard-checkable prerequisites (ignores 'unknown'). */
export function canSelectFeat(checks: PrerequisiteCheck[]): boolean {
  return !checks.some(c => c.status === 'unmet');
}

// ─── Feat Effect Computation ────────────────────────────────

/**
 * Collect all skill bonuses granted by the selected feats.
 *
 * Handles:
 * - Fixed-skill feats (e.g. Magical Aptitude → +2 Spellcraft, +2 UMD)
 * - Compound-ID parameterised feats (e.g. `"skill_focus::Perception"` → +3 Perception)
 *
 * Returns a map of `{ [skillName]: totalBonus }`.
 */
export function computeFeatSkillBonuses(featEntries: string[]): Record<string, number> {
  const bonuses: Record<string, number> = {};

  for (const entry of featEntries) {
    const { featId, choice } = parseFeatEntry(entry);
    const feat = ALL_FEATS.find(f => f.id === featId);
    if (!feat) continue;

    for (const effect of feat.effects) {
      if (effect.type !== 'skill_bonus') continue;

      // Determine the target skill.
      // For parameterised feats (Skill Focus), the effect has
      // `skill: 'chosen skill'` — we replace it with the actual choice.
      let targetSkill = effect.skill;
      if (targetSkill === 'chosen skill') {
        if (!choice) continue; // No choice stored — can't apply
        targetSkill = choice;
      }

      bonuses[targetSkill] = (bonuses[targetSkill] || 0) + effect.bonus;
    }
  }

  return bonuses;
}

/**
 * Returns a display name for a feat entry (including the choice if present).
 * e.g. `"skill_focus::Perception"` → `"Skill Focus (Perception)"`
 */
export function featDisplayName(entry: string): string {
  const { featId, choice } = parseFeatEntry(entry);
  const feat = ALL_FEATS.find(f => f.id === featId);
  const baseName = feat?.name ?? featId;
  return choice ? `${baseName} (${choice})` : baseName;
}

// ─── Comprehensive Feat Stat Bonuses ────────────────────────

/**
 * Aggregated always-on stat bonuses from feats.
 *
 * Only unconditional bonuses are included (i.e. effects without a `condition`).
 * Conditional bonuses (e.g. "when fighting defensively", "with chosen weapon",
 * "against AoOs provoked by movement") are excluded — they require player
 * activation or situational context and will be handled at roll time.
 */
export interface FeatStatBonuses {
  ac: number;
  fortSave: number;
  refSave: number;
  willSave: number;
  initiative: number;
  meleeAttack: number;
  rangedAttack: number;
  /** Flat HP bonus (already accounts for level via Toughness formula). */
  hp: number;
  /** Per-maneuver CMB bonuses (e.g. `{ "grapple": 2, "trip": 2 }`). */
  cmbByManeuver: Record<string, number>;
  /** Per-maneuver CMD bonuses. */
  cmdByManeuver: Record<string, number>;
}

/**
 * Compute all always-on stat bonuses from the selected feats.
 *
 * @param featEntries - The raw feat entry strings (may include compound IDs).
 * @param characterLevel - Current character level (needed for Toughness HP calc).
 */
export function computeFeatStatBonuses(featEntries: string[], characterLevel: number): FeatStatBonuses {
  const result: FeatStatBonuses = {
    ac: 0,
    fortSave: 0,
    refSave: 0,
    willSave: 0,
    initiative: 0,
    meleeAttack: 0,
    rangedAttack: 0,
    hp: 0,
    cmbByManeuver: {},
    cmdByManeuver: {},
  };

  for (const entry of featEntries) {
    const { featId } = parseFeatEntry(entry);
    const feat = ALL_FEATS.find(f => f.id === featId);
    if (!feat) continue;

    for (const effect of feat.effects) {
      switch (effect.type) {
        case 'bonus': {
          // Skip conditional bonuses — they require situational context
          if (effect.condition) break;

          switch (effect.target) {
            case 'ac':
              result.ac += effect.bonus;
              break;
            case 'fort_save':
              result.fortSave += effect.bonus;
              break;
            case 'ref_save':
              result.refSave += effect.bonus;
              break;
            case 'will_save':
              result.willSave += effect.bonus;
              break;
            case 'all_saves':
              result.fortSave += effect.bonus;
              result.refSave += effect.bonus;
              result.willSave += effect.bonus;
              break;
            case 'initiative':
              result.initiative += effect.bonus;
              break;
            case 'attack':
              result.meleeAttack += effect.bonus;
              result.rangedAttack += effect.bonus;
              break;
            case 'melee_attack':
              result.meleeAttack += effect.bonus;
              break;
            case 'ranged_attack':
              result.rangedAttack += effect.bonus;
              break;
          }
          break;
        }

        case 'hp_bonus': {
          // Toughness: +1 HP per level, minimum 3
          const hpFromFeat = Math.max(
            effect.perLevel * characterLevel,
            effect.minimum ?? 0,
          );
          result.hp += hpFromFeat;
          break;
        }

        case 'combat_maneuver': {
          const m = effect.maneuver;
          result.cmbByManeuver[m] = (result.cmbByManeuver[m] || 0) + effect.cmbBonus;
          result.cmdByManeuver[m] = (result.cmdByManeuver[m] || 0) + effect.cmdBonus;
          break;
        }
      }
    }
  }

  return result;
}
