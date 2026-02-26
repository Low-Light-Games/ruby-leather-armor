import React from 'react';
import type { PrerequisiteCheck } from '../../rules/pathfinder_feats';

interface PrereqListProps {
  checks: PrerequisiteCheck[];
}

/** Renders a compact list of prerequisite labels with met/unmet/unknown color coding. */
export const PrereqList: React.FC<PrereqListProps> = ({ checks }) => {
  return (
    <span className="prereq-labels">
      <span className="prereq-prefix">Requires:</span>
      {checks.map((c, i) => (
        <span key={i} className={`prereq-chip prereq-${c.status}`}>
          {c.status === 'met' && '✓ '}
          {c.status === 'unmet' && '✗ '}
          {c.status === 'unknown' && '? '}
          {c.label}
        </span>
      ))}
    </span>
  );
};
