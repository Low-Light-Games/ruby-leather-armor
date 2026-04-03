import React from 'react';
import type { CombatStatCalculation } from './combatCalcTypes';
import { formatCombatCalculationSum } from './formatCombatCalculation';

interface CombatCalculationBlockProps {
  calculation: CombatStatCalculation;
}

/**
 * Renders per-sheet additive breakdown and optional footnotes.
 */
export const CombatCalculationBlock: React.FC<CombatCalculationBlockProps> = ({
  calculation,
}) => {
  const { additive, total, footnotes } = calculation;
  const hasSum = additive.length > 0;
  const hasNotes = footnotes && footnotes.length > 0;

  if (!hasSum && !hasNotes) return null;

  return (
    <div className="csh-calculation">
      <div className="csh-calculation-heading">This character</div>
      {hasSum && (
        <p className="csh-calculation-sum" aria-label="Calculation">
          {formatCombatCalculationSum(additive, total)}
        </p>
      )}
      {hasNotes &&
        footnotes!.map((note, i) => (
          <p key={i} className="csh-calculation-note">
            {note}
          </p>
        ))}
    </div>
  );
};
