import React from 'react';
import type { BattlefieldSnapshot } from '../../types';

interface TacticalMapRailProps {
  combatContext: Record<string, unknown> | null
  battlefield: BattlefieldSnapshot | null | undefined
}

export const TacticalMapRail: React.FC<TacticalMapRailProps> = ({ combatContext, battlefield }) => {
  const active = combatContext?.active === true;
  if (!active || !battlefield) return null;

  const entries = Object.entries(battlefield.tokens || {});

  return (
    <div className="tactical-map-rail context-section" aria-label="Tactical map">
      <div className="context-header">
        <h3>Tactical map</h3>
        <span className="tactical-map-version">v{battlefield.version}</span>
      </div>
      <div className="context-body tactical-map-body">
        <p className="tactical-map-topology">{battlefield.topology} grid</p>
        {entries.length === 0 ? (
          <span className="context-placeholder">No tokens yet.</span>
        ) : (
          <ul className="tactical-token-list">
            {entries.map(([id, t]) => {
              const label = typeof t.label === 'string' ? t.label : id;
              const x = typeof t.x === 'number' ? t.x : null;
              const y = typeof t.y === 'number' ? t.y : null;
              return (
                <li key={id}>
                  <strong>{label}</strong>
                  {x != null && y != null ? ` — (${x}, ${y})` : ''}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
};
