import React, { useCallback } from 'react';
import { useModal } from '../../../hooks/useModal';
import type { CombatStats } from '../hooks/useCombatStats';
import type { CombatGlossaryKey } from '../combatGlossary/types';
import type { CombatStatCalculations } from '../combatHelp/combatCalcTypes';
import { formatMod } from '../../../utils/formatting';
import { CombatStatHelpModal } from '../combatHelp/CombatStatHelpModal';
import { CombatStatGlossaryCell } from '../combatHelp/CombatStatGlossaryCell';

interface CombatStatsSectionProps {
  combatStats: CombatStats;
  combatStatCalculations: CombatStatCalculations;
}

export const CombatStatsSection: React.FC<CombatStatsSectionProps> = ({
  combatStats,
  combatStatCalculations,
}) => {
  const glossary = useModal<CombatGlossaryKey>();
  const closeGlossary = glossary.close;
  const openGlossary = useCallback((key: CombatGlossaryKey) => glossary.open(key), [glossary.open]);

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

      <CombatStatHelpModal
        activeKey={glossary.data}
        onClose={closeGlossary}
        calculation={glossary.data ? combatStatCalculations[glossary.data] : undefined}
      />
    </div>
  );
};
