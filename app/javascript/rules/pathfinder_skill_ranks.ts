/**
 * Client-side skill rank math (budget, per-rank cost, max ranks, stepper validation) for UX.
 *
 * Server enforcement mirrors this logic in CharacterStats::Calculator — see
 * `#effective_rank_bonus` and `#max_ranks_cap` in app/services/character_stats/calculator.rb.
 * Update both when rules change.
 */
import { isClassSkill } from './pathfinder_class_skills';

export type SkillRanksMap = Record<string, number>;

/** Normalize JSON from the server into integer ranks per skill name. */
export function normalizeSkillRanksMap(raw: unknown): SkillRanksMap {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out: SkillRanksMap = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const n = typeof v === 'number' ? v : parseInt(String(v), 10);
    if (Number.isFinite(n) && n > 0) out[k] = Math.floor(n);
  }
  return out;
}

/** Ranks per level after 1st: at least 1 (Pathfinder minimum). */
export function skillPointsPerLevel(skillPointsBase: number, intMod: number): number {
  return Math.max(1, skillPointsBase + intMod);
}

/**
 * Total skill points for a single-class character (approximation: uses current Int mod for all levels).
 * Includes human +1 skill point per level.
 */
export function totalSkillPoints(
  level: number,
  intMod: number,
  skillPointsBase: number,
  raceId: string | null,
): number {
  if (level < 1) return 0;
  const per = skillPointsPerLevel(skillPointsBase, intMod);
  const humanExtra = raceId === 'human' ? level : 0;
  return per * 4 + (level - 1) * per + humanExtra;
}

export function rankPointCost(skillName: string, classId: string | null): number {
  if (!classId) return 2;
  return isClassSkill(skillName, classId) ? 1 : 2;
}

export function maxRanksForSkill(skillName: string, classId: string | null, level: number): number {
  const cap = level + 3;
  if (!classId) return Math.floor(cap / 2);
  return isClassSkill(skillName, classId) ? cap : Math.floor(cap / 2);
}

export function spentSkillPoints(ranks: SkillRanksMap, classId: string | null): number {
  if (!classId) return 0;
  let sum = 0;
  for (const [name, r] of Object.entries(ranks)) {
    const n = Math.max(0, Math.floor(Number(r) || 0));
    if (!n) continue;
    sum += rankPointCost(name, classId) * n;
  }
  return sum;
}

/** Effective ranks applied to the d20 roll (stored ranks capped at legal max). */
export function effectiveRanksStored(
  stored: number,
  skillName: string,
  classId: string | null,
  level: number,
): number {
  const max = maxRanksForSkill(skillName, classId, level);
  return Math.max(0, Math.min(Math.floor(stored || 0), max));
}

export interface TryAdjustSkillRankOpts {
  classId: string | null;
  level: number;
  intMod: number;
  skillPointsBase: number;
  raceId: string | null;
}

/**
 * Returns a new ranks map after a +1 / −1 change, or null if the change is illegal.
 */
export function tryAdjustSkillRank(
  ranks: SkillRanksMap,
  skillName: string,
  delta: 1 | -1,
  opts: TryAdjustSkillRankOpts,
): SkillRanksMap | null {
  const { classId, level, intMod, skillPointsBase, raceId } = opts;
  if (!classId) return null;

  const current = Math.max(0, Math.floor(ranks[skillName] ?? 0));
  const max = maxRanksForSkill(skillName, classId, level);
  const budget = totalSkillPoints(level, intMod, skillPointsBase, raceId);

  if (delta === -1) {
    if (current <= 0) return null;
    const next = { ...ranks, [skillName]: current - 1 };
    if (next[skillName] === 0) delete next[skillName];
    return next;
  }

  if (current >= max) return null;
  const newRank = current + 1;
  const next: SkillRanksMap = { ...ranks, [skillName]: newRank };
  if (spentSkillPoints(next, classId) > budget) return null;
  return next;
}
