import React from 'react';

interface CombatStats {
  ac: number;
  tAC: number;
  ffAC: number;
  cmb: number;
  cmd: number;
  bab: number;
  initiative: number;
  fort: number;
  ref: number;
  will: number;
  hpBonus: number;
}

interface CombatStatsSectionProps {
  combatStats: CombatStats;
}

function formatModifier(mod: number): string {
  return mod >= 0 ? `+${mod}` : `${mod}`;
}

export const CombatStatsSection: React.FC<CombatStatsSectionProps> = ({ combatStats }) => {
  return (
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
        <span className="combat-value">{formatModifier(combatStats.bab)}</span>
      </div>
      <div className="combat-cell">
        <span className="combat-label">Init</span>
        <span className="combat-value">{formatModifier(combatStats.initiative)}</span>
      </div>
      <div className="combat-cell">
        <span className="combat-label">CMB</span>
        <span className="combat-value">{formatModifier(combatStats.cmb)}</span>
      </div>
      <div className="combat-cell">
        <span className="combat-label">CMD</span>
        <span className="combat-value">{combatStats.cmd}</span>
      </div>
      <div className="combat-cell">
        <span className="combat-label">Fort</span>
        <span className="combat-value">{formatModifier(combatStats.fort)}</span>
      </div>
      <div className="combat-cell">
        <span className="combat-label">Ref</span>
        <span className="combat-value">{formatModifier(combatStats.ref)}</span>
      </div>
      <div className="combat-cell">
        <span className="combat-label">Will</span>
        <span className="combat-value">{formatModifier(combatStats.will)}</span>
      </div>
      {combatStats.hpBonus > 0 && (
        <div className="combat-cell">
          <span className="combat-label">HP (Feat)</span>
          <span className="combat-value">+{combatStats.hpBonus}</span>
        </div>
      )}
    </div>
  );
};
