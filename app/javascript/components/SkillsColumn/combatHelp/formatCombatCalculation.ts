import type { CombatCalcTerm } from './combatCalcTypes';

/**
 * Human-readable sum line: "10 (Base) + 2 (Dexterity (effective)) + … = 15"
 */
export function formatCombatCalculationSum(terms: CombatCalcTerm[], total: number): string {
  if (terms.length === 0) return '';
  const body = terms
    .map((t, i) => {
      if (i === 0) return `${t.value} (${t.label})`;
      const sign = t.value >= 0 ? '+' : '';
      return `${sign}${t.value} (${t.label})`;
    })
    .join(' ');
  return `${body} = ${total}`;
}
