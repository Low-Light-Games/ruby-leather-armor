import React from 'react';
import type { CombatGlossaryKey } from '../combatGlossary/types';

interface EncumbranceGlossaryTriggerProps {
  children: React.ReactNode;
  onOpenGlossary: (key: CombatGlossaryKey) => void;
}

/**
 * Wraps encumbrance header content so the load summary opens encumbrance glossary help.
 */
export const EncumbranceGlossaryTrigger: React.FC<EncumbranceGlossaryTriggerProps> = ({
  children,
  onOpenGlossary,
}) => (
  <button
    type="button"
    className="enc-glossary-trigger"
    onClick={() => onOpenGlossary('encumbrance')}
    aria-label="Load and encumbrance: open glossary"
  >
    {children}
  </button>
);
