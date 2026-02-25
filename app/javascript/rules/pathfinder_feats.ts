/**
 * Pathfinder 1e Core Rulebook — Feat aggregator.
 * Re-exports all feat data and provides lookup helpers.
 */

import { FeatDefinition, FeatCategory } from './pathfinder_feats_types';
import { COMBAT_FEATS } from './pathfinder_feats_combat';
import { GENERAL_FEATS, METAMAGIC_FEATS, ITEM_CREATION_FEATS } from './pathfinder_feats_general';

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
