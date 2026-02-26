import React from 'react';
import type { CombatStats } from '../hooks/useCombatStats';
import type { EncumbranceTier } from '../../../rules/pathfinder_items_types';
import { formatMod } from '../../../utils/formatting';

interface CombatStatsSectionProps {
  combatStats: CombatStats;
}

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

export const CombatStatsSection: React.FC<CombatStatsSectionProps> = ({ combatStats }) => {
  const hasEquipment = combatStats.armorBonus > 0 ||
                       combatStats.shieldBonus > 0 ||
                       combatStats.totalACP < 0 ||
                       combatStats.arcaneSpellFailure > 0;

  return (
    <div className="combat-stats-section">
      {/* ── Core combat stats grid ── */}
      <div className="combat-grid">
        <div className="combat-cell">
          <span className="combat-label">AC</span>
          <span className="combat-value">{combatStats.ac}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Touch AC</span>
          <span className="combat-value">{combatStats.tAC}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Flat-Footed</span>
          <span className="combat-value">{combatStats.ffAC}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">BAB</span>
          <span className="combat-value">{formatMod(combatStats.bab)}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Init</span>
          <span className="combat-value">{formatMod(combatStats.initiative)}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Speed</span>
          <span className="combat-value">{combatStats.speed} ft</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">CMB</span>
          <span className="combat-value">{formatMod(combatStats.cmb)}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">CMD</span>
          <span className="combat-value">{combatStats.cmd}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Fort</span>
          <span className="combat-value">{formatMod(combatStats.fort)}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Ref</span>
          <span className="combat-value">{formatMod(combatStats.ref)}</span>
        </div>
        <div className="combat-cell">
          <span className="combat-label">Will</span>
          <span className="combat-value">{formatMod(combatStats.will)}</span>
        </div>
        {combatStats.hpBonus > 0 && (
          <div className="combat-cell">
            <span className="combat-label">HP Bonus</span>
            <span className="combat-value">+{combatStats.hpBonus}</span>
          </div>
        )}
      </div>

      {/* ── Equipment stats (only shown when relevant) ── */}
      {hasEquipment && (
        <>
          <div className="equip-divider">Equipment</div>
          <div className="combat-grid">
            {combatStats.armorBonus > 0 && (
              <div className="combat-cell">
                <span className="combat-label">Armor</span>
                <span className="combat-value">+{combatStats.armorBonus}</span>
              </div>
            )}
            {combatStats.shieldBonus > 0 && (
              <div className="combat-cell">
                <span className="combat-label">Shield</span>
                <span className="combat-value">+{combatStats.shieldBonus}</span>
              </div>
            )}
            {combatStats.totalACP < 0 && (
              <div className="combat-cell">
                <span className="combat-label">ACP</span>
                <span className="combat-value penalty">{combatStats.totalACP}</span>
              </div>
            )}
            {combatStats.arcaneSpellFailure > 0 && (
              <div className="combat-cell">
                <span className="combat-label">Arcane Fail</span>
                <span className="combat-value penalty">{combatStats.arcaneSpellFailure}%</span>
              </div>
            )}
          </div>
        </>
      )}

      {/* ── Encumbrance bar (always shown) ── */}
      <div className="encumbrance-bar">
        <div className="enc-header">
          <span className="enc-label">
            Load: <strong>{combatStats.totalWeight.toFixed(1)} lbs</strong>
          </span>
          <span className={`enc-tier ${ENCUMBRANCE_CLASSES[combatStats.encumbranceTier]}`}>
            {ENCUMBRANCE_LABELS[combatStats.encumbranceTier]}
          </span>
        </div>
        <div className="enc-track">
          <div
            className={`enc-fill ${ENCUMBRANCE_CLASSES[combatStats.encumbranceTier]}`}
            style={{
              width: `${Math.min(
                (combatStats.totalWeight / Math.max(combatStats.carryCapacity.heavy, 1)) * 100,
                100,
              )}%`,
            }}
          />
          {/* Threshold markers */}
          <div
            className="enc-marker light-marker"
            style={{
              left: `${(combatStats.carryCapacity.light / Math.max(combatStats.carryCapacity.heavy, 1)) * 100}%`,
            }}
          />
          <div
            className="enc-marker medium-marker"
            style={{
              left: `${(combatStats.carryCapacity.medium / Math.max(combatStats.carryCapacity.heavy, 1)) * 100}%`,
            }}
          />
        </div>
        <div className="enc-thresholds">
          <span>Light ≤{combatStats.carryCapacity.light}</span>
          <span>Med ≤{combatStats.carryCapacity.medium}</span>
          <span>Heavy ≤{combatStats.carryCapacity.heavy}</span>
        </div>
      </div>
    </div>
  );
};
