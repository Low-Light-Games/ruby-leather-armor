/**
 * Pathfinder 1e Unarmed Strike damage.
 * Monk unarmed damage scales with level per the Core Rulebook Table 3-10.
 * All other classes deal 1d3 nonlethal (Medium creature).
 * Pure game mechanics — Open Game Content.
 */

const MONK_UNARMED_DICE: [number, string][] = [
  [20, '2d10'],
  [16, '2d8'],
  [12, '2d6'],
  [8,  '1d10'],
  [4,  '1d8'],
  [1,  '1d6'],
];

const DEFAULT_UNARMED_DICE = '1d3';

export function getUnarmedDamageDice(classId: string | null, level: number): string {
  if (classId?.toLowerCase() === 'monk') {
    for (const [minLevel, dice] of MONK_UNARMED_DICE) {
      if (level >= minLevel) return dice;
    }
  }
  return DEFAULT_UNARMED_DICE;
}
