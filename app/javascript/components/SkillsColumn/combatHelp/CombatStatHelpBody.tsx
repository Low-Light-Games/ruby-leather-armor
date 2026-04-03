import React from 'react';
import type { CombatGlossaryEntry } from '../combatGlossary/types';
import type { CombatStatCalculation } from './combatCalcTypes';
import { CombatCalculationBlock } from './CombatCalculationBlock';

interface CombatStatHelpBodyProps {
  entry: CombatGlossaryEntry;
  calculation?: CombatStatCalculation;
}

/**
 * Renders glossary paragraphs and optional per-sheet calculation for the combat help modal.
 */
export const CombatStatHelpBody: React.FC<CombatStatHelpBodyProps> = ({
  entry,
  calculation,
}) => (
  <div className="csh-body">
    {entry.paragraphs.map((text, i) => (
      <p key={i} className="csh-paragraph">
        {text}
      </p>
    ))}
    {calculation && <CombatCalculationBlock calculation={calculation} />}
  </div>
);
