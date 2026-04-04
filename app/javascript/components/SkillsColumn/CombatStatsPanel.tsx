import React from 'react';
import type { CombatStats } from './hooks/useCombatStats';
import type { CombatStatCalculations } from './combatHelp/combatCalcTypes';
import { CombatStatsSection } from './sections/CombatStatsSection';

export interface CombatStatsPanelProps {
  combatStats: CombatStats;
  combatStatCalculations: CombatStatCalculations;
}

export const CombatStatsPanel: React.FC<CombatStatsPanelProps> = ({
  combatStats,
  combatStatCalculations,
}) => (
  <div className="combat-stats-panel">
    <div className="combat-stats-panel-header">Combat Stats</div>
    <div className="combat-stats-panel-body">
      <CombatStatsSection
        combatStats={combatStats}
        combatStatCalculations={combatStatCalculations}
      />
    </div>
  </div>
);
