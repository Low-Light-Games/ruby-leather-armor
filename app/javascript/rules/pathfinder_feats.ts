/**
 * Pathfinder 1e Core Rulebook — Feat aggregator.
 * Re-exports all feat data and provides lookup helpers.
 */

import { AttributeType } from '../types';
import { FeatDefinition, FeatCategory, Prerequisite } from './pathfinder_feats_types';
import { COMBAT_FEATS } from './pathfinder_feats_combat';
import { GENERAL_FEATS, METAMAGIC_FEATS, ITEM_CREATION_FEATS } from './pathfinder_feats_general';
import type { BABProgression } from './pathfinder_classes';

export type { FeatDefinition, FeatCategory } from './pathfinder_feats_types';
export type { Prerequisite, FeatEffect, BonusTarget } from './pathfinder_feats_types';

/** All Core Rulebook feats in one flat array. */
export const ALL_FEATS: FeatDefinition[] = [
  ...COMBAT_FEATS,
  ...GENERAL_FEATS,
  ...METAMAGIC_FEATS,
  ...ITEM_CREATION_FEATS,
];

/** Lookup a feat by its id. */
export function getFeatById(id: string): FeatDefinition | undefined {
  return ALL_FEATS.find(f => f.id === id);
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
 */
export function hasFeatPrerequisites(
  targetFeatId: string,
  ownedFeatIds: Set<string>,
): boolean {
  const feat = getFeatById(targetFeatId);
  if (!feat) return false;
  return feat.prerequisites
    .filter(p => p.type === 'feat')
    .every(p => ownedFeatIds.has((p as { type: 'feat'; feat: string }).feat));
}

// ─── Prerequisite Checking System ────────────────────────────

/** Compute BAB at a given level for a given BAB progression. */
export function computeBAB(bab: BABProgression, level: number): number {
  switch (bab) {
    case 'full':  return level;
    case '3/4':   return Math.floor(level * 3 / 4);
    case '1/2':   return Math.floor(level / 2);
  }
}

/** Character state needed to evaluate feat prerequisites. */
export interface PrerequisiteContext {
  finalAttributes: Record<AttributeType, number>;
  level: number;
  classId: string | null;
  bab: number;
  ownedFeatIds: Set<string>;
}

/** Status of a single prerequisite check. */
export type PrereqStatus = 'met' | 'unmet' | 'unknown';

/** Result of checking one prerequisite. */
export interface PrerequisiteCheck {
  label: string;
  status: PrereqStatus;
}

const ABILITY_ABBR: Record<string, string> = {
  strength: 'STR', dexterity: 'DEX', constitution: 'CON',
  intelligence: 'INT', wisdom: 'WIS', charisma: 'CHA',
};

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
    case 'class_feature':
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
        status = ctx.ownedFeatIds.has(prereq.feat) ? 'met' : 'unmet';
        break;
      case 'character_level':
        status = ctx.level >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'class_level':
        status = (ctx.classId === prereq.classId && ctx.level >= prereq.level) ? 'met' : 'unmet';
        break;
      default:
        // skill, caster_level, class_feature, proficiency — can't fully verify
        status = 'unknown';
    }

    return { label, status };
  });
}

/** Returns true if the character meets all hard-checkable prerequisites (ignores 'unknown'). */
export function canSelectFeat(checks: PrerequisiteCheck[]): boolean {
  return !checks.some(c => c.status === 'unmet');
}
