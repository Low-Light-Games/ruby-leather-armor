import React, { useState, useRef, useCallback } from 'react'
import type { StatBreakdownLine } from '../../types'

interface StatTooltipProps {
  children: React.ReactNode
  label: string
  total: number | string
  breakdown?: StatBreakdownLine[]
}

const StatTooltip: React.FC<StatTooltipProps> = ({ children, label, total, breakdown }) => {
  const [visible, setVisible] = useState(false)
  const ref = useRef<HTMLSpanElement>(null)

  const show = useCallback(() => setVisible(true), [])
  const hide = useCallback(() => setVisible(false), [])

  if (!breakdown || breakdown.length === 0) {
    return <>{children}</>
  }

  return (
    <span
      className="stat-tooltip-wrapper"
      ref={ref}
      onMouseEnter={show}
      onMouseLeave={hide}
      onFocus={show}
      onBlur={hide}
      tabIndex={0}
    >
      {children}
      {visible && (
        <div className="stat-tooltip-popup" role="tooltip">
          <div className="stat-tooltip-header">
            <span>{label}</span>
            <span className="stat-tooltip-total">{total}</span>
          </div>
          <div className="stat-tooltip-rows">
            {breakdown.map((entry, i) => {
              const isCondition = entry.type === 'condition'
              const numVal = typeof entry.value === 'number' ? entry.value : parseFloat(String(entry.value))
              const formatted = !isNaN(numVal) && numVal > 0 && entry.label !== 'Base'
                ? `+${numVal}`
                : String(entry.value)

              return (
                <div
                  key={`${entry.label}-${i}`}
                  className={`stat-tooltip-row ${isCondition ? 'condition-entry' : ''}`}
                >
                  <span className="stat-tooltip-label">{entry.label}</span>
                  <span className={`stat-tooltip-value ${numVal < 0 ? 'negative' : ''}`}>
                    {formatted}
                  </span>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </span>
  )
}

export default StatTooltip
