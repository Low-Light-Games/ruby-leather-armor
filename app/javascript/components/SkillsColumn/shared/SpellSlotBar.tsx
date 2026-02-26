import React from 'react';
import type { SpellSlotSummary } from '../../../rules/pathfinder_spells';

interface SpellSlotBarProps {
  slots: SpellSlotSummary[];
}

export const SpellSlotBar: React.FC<SpellSlotBarProps> = ({ slots }) => {
  if (slots.length === 0) return null;

  return (
    <div className="spell-slot-bar">
      {slots.map(slot => (
        <div
          key={slot.spellLevel}
          className={`slot-counter ${slot.remaining === 0 && slot.limit !== Infinity ? 'slot-full' : ''}`}
        >
          <span className="slot-label">{slot.label}</span>
          <span className="slot-fraction">
            {slot.limit === Infinity
              ? `${slot.used} (auto)`
              : `${slot.used}/${slot.limit}`}
          </span>
        </div>
      ))}
    </div>
  );
};
