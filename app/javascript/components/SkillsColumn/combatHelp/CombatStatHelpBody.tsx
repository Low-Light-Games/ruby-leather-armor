import React from 'react';
import type { CombatGlossaryEntry } from '../combatGlossary/types';

interface CombatStatHelpBodyProps {
  entry: CombatGlossaryEntry;
}

/**
 * Renders glossary paragraphs for the combat stat help modal.
 */
export const CombatStatHelpBody: React.FC<CombatStatHelpBodyProps> = ({ entry }) => (
  <div className="csh-body">
    {entry.paragraphs.map((text, i) => (
      <p key={i} className="csh-paragraph">
        {text}
      </p>
    ))}
  </div>
);
