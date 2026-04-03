/**
 * Per-sheet combat stat breakdown shown under glossary text in help modals.
 * Additive lines are intended to sum to `total` (same as the value on the sheet).
 */

import type { CombatGlossaryKey } from '../combatGlossary/types';

export interface CombatCalcTerm {
  value: number;
  label: string;
}

export interface CombatStatCalculation {
  /** Display total — should match the stat shown on the character sheet. */
  total: number;
  /** Summands in display order (first term is usually written without a leading +). */
  additive: CombatCalcTerm[];
  /** Optional notes (e.g. caps, speed rules). */
  footnotes?: string[];
}

export type CombatStatCalculations = Record<CombatGlossaryKey, CombatStatCalculation>;
