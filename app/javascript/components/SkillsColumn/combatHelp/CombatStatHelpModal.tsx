import React, { useEffect } from 'react';
import type { CombatGlossaryKey } from '../combatGlossary/types';
import { getCombatGlossaryEntry } from '../combatGlossary';
import type { CombatStatCalculation } from './combatCalcTypes';
import { CombatStatHelpBody } from './CombatStatHelpBody';

interface CombatStatHelpModalProps {
  activeKey: CombatGlossaryKey | null;
  calculation?: CombatStatCalculation | null;
  onClose: () => void;
}

/**
 * Lightweight glossary modal for a single combat stat key.
 */
export const CombatStatHelpModal: React.FC<CombatStatHelpModalProps> = ({
  activeKey,
  calculation,
  onClose,
}) => {
  useEffect(() => {
    if (!activeKey) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [activeKey, onClose]);

  if (!activeKey) return null;

  const entry = getCombatGlossaryEntry(activeKey);

  return (
    <div
      className="csh-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="csh-title"
      onClick={onClose}
    >
      <div className="csh-modal" onClick={e => e.stopPropagation()}>
        <div className="csh-header">
          <h3 id="csh-title">{entry.title}</h3>
          <button type="button" className="csh-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </div>
        <CombatStatHelpBody entry={entry} calculation={calculation ?? undefined} />
      </div>
    </div>
  );
};
