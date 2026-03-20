import React, { useState } from 'react'
import { getCondition } from '../../../rules/pathfinder_conditions'

interface ConditionsBadgesProps {
  conditions: string[]
  restrictions: string[]
}

const ConditionsBadges: React.FC<ConditionsBadgesProps> = ({ conditions, restrictions }) => {
  const [hoveredCondition, setHoveredCondition] = useState<string | null>(null)

  if (conditions.length === 0) return null

  return (
    <div className="conditions-strip">
      <div className="conditions-badges">
        {conditions.map(cond => {
          const def = getCondition(cond)
          const label = def?.label ?? cond
          const colorClass = def?.color ?? 'slate'

          return (
            <span
              key={cond}
              className={`condition-badge badge-${colorClass}`}
              onMouseEnter={() => setHoveredCondition(cond)}
              onMouseLeave={() => setHoveredCondition(null)}
            >
              {label}
              {hoveredCondition === cond && def && (
                <span className="condition-tooltip" role="tooltip">
                  {def.description}
                </span>
              )}
            </span>
          )
        })}
      </div>
      {restrictions.length > 0 && (
        <div className="conditions-restrictions">
          {restrictions.map(r => (
            <span key={r} className="restriction-tag">
              {r.replace(/_/g, ' ')}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}

export default ConditionsBadges
