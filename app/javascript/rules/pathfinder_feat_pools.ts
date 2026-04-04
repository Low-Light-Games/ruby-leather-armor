/**
 * Pathfinder 1e feat slot pools (character sheet builder).
 * Pools determine which feats can fill which slots (e.g. fighter bonus → combat only).
 */

import type { FeatCategory } from './pathfinder_feats_types';
import { getAllFeats } from './pathfinder_feats';

/** Separator between pool id and feat entry in stored strings. */
export const FEAT_POOL_SEPARATOR = '|';

/** Stable ids persisted on SheetFeat.pool and in encoded client strings. */
export type FeatPoolId = 'general' | 'human_bonus' | 'fighter_bonus_combat';

export const FEAT_POOL_IDS: FeatPoolId[] = ['general', 'human_bonus', 'fighter_bonus_combat'];

export function isFeatPoolId(s: string): s is FeatPoolId {
  return (FEAT_POOL_IDS as string[]).includes(s);
}

/** General feats: 1st, 3rd, 5th, … (odd levels from 1). */
export function generalFeatSlotCount(level: number): number {
  if (level < 1) return 0;
  return Math.floor((level + 1) / 2);
}

/** Human racial bonus feat (extra at 1st). */
export function humanBonusFeatSlotCount(level: number, raceId: string | null): number {
  if (level < 1 || raceId !== 'human') return 0;
  return 1;
}

/**
 * Fighter bonus combat feats: 1st, 2nd, 4th, 6th, …
 * Count at level L = 1 + floor(L / 2) for L >= 1.
 */
export function fighterBonusCombatFeatSlotCount(level: number, classId: string | null): number {
  if (level < 1 || classId !== 'fighter') return 0;
  return 1 + Math.floor(level / 2);
}

export interface FeatPoolDefinition {
  id: FeatPoolId;
  title: string;
  /** Shown under the title — why this pool exists and what may go here. */
  explanation: string;
  /** null = any feat category allowed */
  allowedCategories: FeatCategory[] | null;
  maxSlots: number;
}

/**
 * Describe every pool that applies to this character (max may be 0; still listed for clarity when useful).
 */
export function describeFeatPools(
  level: number,
  raceId: string | null,
  classId: string | null,
): FeatPoolDefinition[] {
  const pools: FeatPoolDefinition[] = [];

  const gMax = generalFeatSlotCount(level);
  pools.push({
    id: 'general',
    title: 'General feats',
    explanation:
      `You gain a general feat at 1st level and every 2 character levels after (3rd, 5th, 7th, …). ` +
      `At level ${level}, you have ${gMax} general feat slot${gMax === 1 ? '' : 's'}. ` +
      `Any feat you qualify for can use a general slot.`,
    allowedCategories: null,
    maxSlots: gMax,
  });

  const hMax = humanBonusFeatSlotCount(level, raceId);
  pools.push({
    id: 'human_bonus',
    title: 'Human bonus feat',
    explanation:
      hMax > 0
        ? 'Human racial trait: one extra feat at 1st level. It can be any feat you qualify for, including combat feats.'
        : 'Only humans get an extra feat at 1st level. Choose Human as your race to unlock this pool.',
    allowedCategories: null,
    maxSlots: hMax,
  });

  const fMax = fighterBonusCombatFeatSlotCount(level, classId);
  pools.push({
    id: 'fighter_bonus_combat',
    title: 'Fighter bonus feats (combat only)',
    explanation:
      fMax > 0
        ? `A fighter gains a bonus combat feat at 1st level and every even level after (2nd, 4th, 6th, …). ` +
          `At level ${level}, you have ${fMax} fighter bonus feat slot${fMax === 1 ? '' : 's'}. ` +
          `Only feats with the Combat category can fill these slots.`
        : 'Fighter bonus combat feat slots apply only to the fighter class. Choose Fighter to unlock this pool.',
    allowedCategories: fMax > 0 ? ['combat'] : ['combat'],
    maxSlots: fMax,
  });

  return pools;
}

export function poolAllowsFeatCategory(
  pool: FeatPoolDefinition,
  category: FeatCategory,
): boolean {
  if (pool.allowedCategories === null) return true;
  return pool.allowedCategories.includes(category);
}

/** Encode for API / SheetFeat: `poolId|featId` or `poolId|featId::choice` */
export function encodeFeatSlot(poolId: FeatPoolId, rawEntry: string): string {
  return `${poolId}${FEAT_POOL_SEPARATOR}${rawEntry}`;
}

export interface DecodedFeatSlot {
  poolId: FeatPoolId;
  /** Feat id or feat id::choice (no pool prefix). */
  rawEntry: string;
}

/**
 * Decode stored string. Legacy entries without `|` are treated as general pool.
 */
export function decodeFeatSlot(encoded: string): DecodedFeatSlot {
  const idx = encoded.indexOf(FEAT_POOL_SEPARATOR);
  if (idx === -1) {
    return { poolId: 'general', rawEntry: encoded };
  }
  const poolPart = encoded.slice(0, idx);
  const rawEntry = encoded.slice(idx + 1);
  const poolId: FeatPoolId = isFeatPoolId(poolPart) ? poolPart : 'general';
  return { poolId, rawEntry };
}

/** Migrate legacy flat feat list to encoded slots (all general). */
export function migrateToPooledFormat(entries: string[]): string[] {
  return entries.map(f => {
    if (f.includes(FEAT_POOL_SEPARATOR)) return f;
    return encodeFeatSlot('general', f);
  });
}

export function migrateFeatListToPooled(feats: string[]): string[] {
  return migrateToPooledFormat(feats);
}

/** Strip pool prefix for prerequisite / duplicate checks on raw feat entries. */
export function featListRawEntries(encodedList: string[]): string[] {
  return encodedList.map(e => decodeFeatSlot(e).rawEntry);
}

/**
 * Feat string encoding/decoding and migration — separated from pool slot math (counts, UI copy).
 */
export const FeatMigrationUtils = {
  parsePooledEntry: decodeFeatSlot,
  migrateToPooledFormat,
  validatePoolAssignment(
    featId: string,
    poolId: FeatPoolId,
    ctx: { level: number; raceId: string | null; classId: string | null },
  ): { ok: boolean; reason?: string } {
    const feat = getAllFeats().find(f => f.id === featId);
    if (!feat) return { ok: false, reason: 'Unknown feat' };
    const poolDef = describeFeatPools(ctx.level, ctx.raceId, ctx.classId).find(p => p.id === poolId);
    if (!poolDef) return { ok: false, reason: 'Unknown pool' };
    if (poolDef.maxSlots <= 0) return { ok: false, reason: 'Pool has no slots at this level' };
    if (!poolAllowsFeatCategory(poolDef, feat.category)) {
      return { ok: false, reason: 'Feat category not allowed in this pool' };
    }
    return { ok: true };
  },
} as const;
