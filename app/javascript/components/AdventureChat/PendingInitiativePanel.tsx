import { useState, useRef, useEffect } from 'react'
import type { DerivedStats } from '../../types'
import { formatMod } from '../../utils/formatting'
import { rollD20 } from '../../rules/dice'

interface PendingInitiativePanelProps {
  derivedStats?: DerivedStats | null
  onSubmit: (value: number) => void
}

const PendingInitiativePanel = ({ derivedStats, onSubmit }: PendingInitiativePanelProps) => {
  const [value, setValue] = useState<number | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    inputRef.current?.focus()
  }, [])

  const initiativeMod = derivedStats?.initiative ?? 0

  const handleRoll = () => {
    const result = rollD20(initiativeMod)
    setValue(result.total)
    onSubmit(result.total)
  }

  const handleManualChange = (raw: string) => {
    const v = parseInt(raw, 10)
    setValue(isNaN(v) ? null : v)
  }

  const handleSubmit = () => {
    if (value != null) onSubmit(value)
  }

  return (
    <div className="roll-submit-area">
      <div className="roll-prompt-header">⚔️ Roll for Initiative!</div>
      <div className="roll-entry">
        <div className="roll-prompt">
          <span className="roll-prompt-type">Initiative</span>
          {derivedStats && (
            <span className="roll-modifier">{formatMod(initiativeMod)}</span>
          )}
        </div>
        <div className="roll-actions">
          {derivedStats ? (
            <button
              className={`roll-btn roll-d20 ${value != null ? 'roll-done' : ''}`}
              onClick={handleRoll}
              disabled={value != null}
            >
              {value != null ? `Rolled: ${value}` : `Roll d20 (${formatMod(initiativeMod)})`}
            </button>
          ) : (
            <input
              ref={inputRef}
              type="number"
              min="1"
              max="30"
              placeholder="Enter roll result"
              value={value ?? ''}
              onChange={e => handleManualChange(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter' && value != null) handleSubmit()
              }}
              className="roll-input"
            />
          )}
        </div>
      </div>
      {!derivedStats && (
        <button
          onClick={handleSubmit}
          disabled={value == null}
          className="roll-submit-btn"
        >
          Submit Initiative
        </button>
      )}
    </div>
  )
}

export default PendingInitiativePanel
