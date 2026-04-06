import React from 'react';
import type { CarryCapacity, EncumbranceTier } from '../../../rules/pathfinder_items_types';
import type { CombatGlossaryKey } from '../combatGlossary/types';
import { EncumbranceGlossaryTrigger } from './EncumbranceGlossaryTrigger';
import { CombatStatInfoIcon } from './CombatStatInfoIcon';

const ENCUMBRANCE_LABELS: Record<EncumbranceTier, string> = {
  light: 'Light',
  medium: 'Medium',
  heavy: 'Heavy',
  overloaded: 'Overloaded',
};

const ENCUMBRANCE_CLASSES: Record<EncumbranceTier, string> = {
  light: 'enc-light',
  medium: 'enc-medium',
  heavy: 'enc-heavy',
  overloaded: 'enc-overloaded',
};

export interface EncumbranceBarPanelProps {
  totalWeight: number;
  encumbranceTier: EncumbranceTier;
  carryCapacity: CarryCapacity;
  onOpenGlossary: (key: CombatGlossaryKey) => void;
}

/**
 * Load weight, tier badge, and threshold track (used under Equipment).
 */
export const EncumbranceBarPanel: React.FC<EncumbranceBarPanelProps> = ({
  totalWeight,
  encumbranceTier,
  carryCapacity,
  onOpenGlossary,
}) => (
  <div className="encumbrance-bar encumbrance-bar--equipment-top">
    <div className="enc-header">
      <EncumbranceGlossaryTrigger onOpenGlossary={onOpenGlossary}>
        <span className="enc-label">
          Load: <strong>{totalWeight.toFixed(1)} lbs</strong>
        </span>
        <span className="enc-glossary-tier-wrap">
          <span className={`enc-tier ${ENCUMBRANCE_CLASSES[encumbranceTier]}`}>
            {ENCUMBRANCE_LABELS[encumbranceTier]}
          </span>
          <CombatStatInfoIcon className="enc-glossary-info-icon" />
        </span>
      </EncumbranceGlossaryTrigger>
    </div>
    <div className="enc-track">
      <div
        className={`enc-fill ${ENCUMBRANCE_CLASSES[encumbranceTier]}`}
        style={{
          width: `${Math.min(
            (totalWeight / Math.max(carryCapacity.heavy, 1)) * 100,
            100,
          )}%`,
        }}
      />
      <div
        className="enc-marker light-marker"
        style={{
          left: `${(carryCapacity.light / Math.max(carryCapacity.heavy, 1)) * 100}%`,
        }}
      />
      <div
        className="enc-marker medium-marker"
        style={{
          left: `${(carryCapacity.medium / Math.max(carryCapacity.heavy, 1)) * 100}%`,
        }}
      />
    </div>
    <div className="enc-thresholds">
      <span>Light ≤{carryCapacity.light}</span>
      <span>Med ≤{carryCapacity.medium}</span>
      <span>Heavy ≤{carryCapacity.heavy}</span>
    </div>
  </div>
);
