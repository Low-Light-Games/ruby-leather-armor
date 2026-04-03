import React, { useState, useCallback } from 'react';
import type { CombatStats } from '../hooks/useCombatStats';
import type { EncumbranceTier } from '../../../rules/pathfinder_items_types';
import type { CombatGlossaryKey } from '../combatGlossary/types';
import { formatMod } from '../../../utils/formatting';
import { CombatStatHelpModal } from '../combatHelp/CombatStatHelpModal';
import { CombatStatGlossaryCell } from '../combatHelp/CombatStatGlossaryCell';
import { EncumbranceGlossaryTrigger } from '../combatHelp/EncumbranceGlossaryTrigger';
import { CombatStatInfoIcon } from '../combatHelp/CombatStatInfoIcon';

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
  const [glossaryKey, setGlossaryKey] = useState<CombatGlossaryKey | null>(null);
  const closeGlossary = useCallback(() => setGlossaryKey(null), []);
  const openGlossary = useCallback((key: CombatGlossaryKey) => setGlossaryKey(key), []);

  const hasEquipment = combatStats.armorBonus > 0 ||
                       combatStats.shieldBonus > 0 ||
                       combatStats.totalACP < 0 ||
                       combatStats.arcaneSpellFailure > 0;

  return (
    <div className="combat-stats-section">
      <div className="combat-grid">
        <CombatStatGlossaryCell
          glossaryKey="ac"
          label="AC"
          value={combatStats.ac}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="touchAc"
          label="Touch AC"
          value={combatStats.tAC}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="flatFooted"
          label="Flat-Footed"
          value={combatStats.ffAC}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="bab"
          label="BAB"
          value={formatMod(combatStats.bab)}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="initiative"
          label="Init"
          value={formatMod(combatStats.initiative)}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="speed"
          label="Speed"
          value={`${combatStats.speed} ft`}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="cmb"
          label="CMB"
          value={formatMod(combatStats.cmb)}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="cmd"
          label="CMD"
          value={combatStats.cmd}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="fort"
          label="Fort"
          value={formatMod(combatStats.fort)}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="ref"
          label="Ref"
          value={formatMod(combatStats.ref)}
          onOpenGlossary={openGlossary}
        />
        <CombatStatGlossaryCell
          glossaryKey="will"
          label="Will"
          value={formatMod(combatStats.will)}
          onOpenGlossary={openGlossary}
        />
        {combatStats.hpBonus > 0 && (
          <CombatStatGlossaryCell
            glossaryKey="hpBonus"
            label="HP Bonus"
            value={`+${combatStats.hpBonus}`}
            onOpenGlossary={openGlossary}
          />
        )}
      </div>

      {hasEquipment && (
        <>
          <div className="equip-divider">Equipment</div>
          <div className="combat-grid">
            {combatStats.armorBonus > 0 && (
              <CombatStatGlossaryCell
                glossaryKey="armorBonus"
                label="Armor"
                value={`+${combatStats.armorBonus}`}
                onOpenGlossary={openGlossary}
              />
            )}
            {combatStats.shieldBonus > 0 && (
              <CombatStatGlossaryCell
                glossaryKey="shieldBonus"
                label="Shield"
                value={`+${combatStats.shieldBonus}`}
                onOpenGlossary={openGlossary}
              />
            )}
            {combatStats.totalACP < 0 && (
              <CombatStatGlossaryCell
                glossaryKey="acp"
                label="ACP"
                value={combatStats.totalACP}
                valueClassName="penalty"
                onOpenGlossary={openGlossary}
              />
            )}
            {combatStats.arcaneSpellFailure > 0 && (
              <CombatStatGlossaryCell
                glossaryKey="arcaneSpellFailure"
                label="Arcane Fail"
                value={`${combatStats.arcaneSpellFailure}%`}
                valueClassName="penalty"
                onOpenGlossary={openGlossary}
              />
            )}
          </div>
        </>
      )}

      <div className="encumbrance-bar">
        <div className="enc-header">
          <EncumbranceGlossaryTrigger onOpenGlossary={openGlossary}>
            <span className="enc-label">
              Load: <strong>{combatStats.totalWeight.toFixed(1)} lbs</strong>
            </span>
            <span className="enc-glossary-tier-wrap">
              <span className={`enc-tier ${ENCUMBRANCE_CLASSES[combatStats.encumbranceTier]}`}>
                {ENCUMBRANCE_LABELS[combatStats.encumbranceTier]}
              </span>
              <CombatStatInfoIcon className="enc-glossary-info-icon" />
            </span>
          </EncumbranceGlossaryTrigger>
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

      <CombatStatHelpModal activeKey={glossaryKey} onClose={closeGlossary} />
    </div>
  );
};
