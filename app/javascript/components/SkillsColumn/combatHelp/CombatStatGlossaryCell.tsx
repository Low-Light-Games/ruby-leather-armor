import React from 'react';
import type { CombatGlossaryKey } from '../combatGlossary/types';
import { CombatStatInfoIcon } from './CombatStatInfoIcon';

interface CombatStatGlossaryCellProps {
  glossaryKey: CombatGlossaryKey;
  label: string;
  value: React.ReactNode;
  valueClassName?: string;
  onOpenGlossary: (key: CombatGlossaryKey) => void;
}

/**
 * One combat stat tile: opens glossary help on activate.
 */
export const CombatStatGlossaryCell: React.FC<CombatStatGlossaryCellProps> = ({
  glossaryKey,
  label,
  value,
  valueClassName,
  onOpenGlossary,
}) => (
  <button
    type="button"
    className="combat-cell combat-glossary-cell"
    onClick={() => onOpenGlossary(glossaryKey)}
    aria-label={`${label}: open glossary`}
  >
    <span className="combat-glossary-cell-head">
      <span className="combat-label">
        {label}
        <CombatStatInfoIcon className="combat-glossary-info-icon" />  
      </span>
      
    </span>
    <span className={`combat-value${valueClassName ? ` ${valueClassName}` : ''}`}>{value}</span>
  </button>
);
