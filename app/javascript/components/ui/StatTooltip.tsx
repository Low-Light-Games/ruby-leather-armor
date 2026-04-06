import React, { useState, useRef, useCallback, useLayoutEffect } from 'react'
import { createPortal } from 'react-dom'
import type { StatBreakdownLine } from '../../types'

interface StatTooltipProps {
  children: React.ReactNode
  label: string
  total: number | string
  breakdown?: StatBreakdownLine[]
}

const StatTooltip: React.FC<StatTooltipProps> = ({ children, label, total, breakdown }) => {
  const [visible, setVisible] = useState(false)
  const [popupStyle, setPopupStyle] = useState<React.CSSProperties>({})
  const anchorRef = useRef<HTMLSpanElement>(null)
  const popupRef = useRef<HTMLDivElement>(null)

  const show = useCallback(() => setVisible(true), [])
  const hide = useCallback(() => {
    setVisible(false)
    setPopupStyle({})
  }, [])

  useLayoutEffect(() => {
    if (!visible) return

    const updatePosition = () => {
      const anchor = anchorRef.current
      if (!anchor) return

      const rect = anchor.getBoundingClientRect()
      let centerX = rect.left + rect.width / 2
      const top = rect.top - 8
      const popup = popupRef.current
      if (popup) {
        const w = popup.getBoundingClientRect().width
        // Before position:fixed applies, a block-level node in body can span the full viewport; skip bad clamp.
        if (w > 0 && w < window.innerWidth * 0.9) {
          const halfW = w / 2
          const margin = 8
          centerX = Math.max(margin + halfW, Math.min(window.innerWidth - margin - halfW, centerX))
        }
      }
      setPopupStyle({
        position: 'fixed',
        left: centerX,
        top,
        transform: 'translate(-50%, -100%)',
        visibility: 'visible',
      })
    }

    updatePosition()
    const rafId = requestAnimationFrame(() => updatePosition())
    window.addEventListener('scroll', updatePosition, true)
    window.addEventListener('resize', updatePosition)
    return () => {
      cancelAnimationFrame(rafId)
      window.removeEventListener('scroll', updatePosition, true)
      window.removeEventListener('resize', updatePosition)
    }
  }, [visible, label, total, breakdown])

  if (!breakdown || breakdown.length === 0) {
    return <>{children}</>
  }

  const popup = visible && (
    <div
      ref={popupRef}
      className="stat-tooltip-popup"
      role="tooltip"
      style={popupStyle}
    >
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
  )

  return (
    <div
      className="stat-tooltip-wrapper"
      ref={anchorRef}
      onMouseEnter={show}
      onMouseLeave={hide}
      onFocus={show}
      onBlur={hide}
      tabIndex={0}
    >
      {children}
      {typeof document !== 'undefined' && popup ? createPortal(popup, document.body) : null}
    </div>
  )
}

export default StatTooltip
