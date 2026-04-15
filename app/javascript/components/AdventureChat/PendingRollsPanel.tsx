import { useRef, useEffect } from 'react'
import type { DerivedStats } from '../../types'
import { formatMod } from '../../utils/formatting'
import { rollD20 } from '../../rules/dice'
import type { RollResultDisplay } from '../RollResultModal'
import { rollLabel, PendingRolls, ResolutionMethod } from './rollHelpers'

interface PendingRollsPanelProps {
  pendingRolls: PendingRolls
  derivedStats?: DerivedStats | null
  onRollValueChange: (index: number, value: number, method: ResolutionMethod) => void
  onSubmit: () => void
  allRollsFilled: boolean
  onRollModal: (index: number, display: RollResultDisplay) => void
}

const PendingRollsPanel = ({
  pendingRolls, derivedStats,
  onRollValueChange, onSubmit, allRollsFilled, onRollModal,
}: PendingRollsPanelProps) => {
  const rollInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    rollInputRef.current?.focus()
  }, [])

  const handleRollD20 = (index: number) => {
    const entry = pendingRolls.entries[index]
    if (!entry.resolved) return

    const result = rollD20(entry.resolved.modifier)
    onRollModal(index, {
      label: entry.resolved.label,
      result,
      modifierLabel: entry.resolved.modifierLabel,
    })
  }

  const handleManualRollChange = (index: number, raw: string) => {
    const v = parseInt(raw, 10)
    onRollValueChange(index, isNaN(v) ? 0 : v, 'manual')
  }

  return (
    <div className="roll-submit-area">
      <div className="roll-prompt-header">🎲 Rolls Needed</div>
      {pendingRolls.entries.map((entry, i) => {
        const { request: req, resolved, value } = entry
        const isHallucination = derivedStats && !resolved

        return (
          <div key={i} className={`roll-entry ${isHallucination ? 'roll-unresolved' : ''}`}>
            <div className="roll-prompt">
              <span className="roll-prompt-type">
                {resolved ? resolved.label : rollLabel(req)}
              </span>
              {pendingRolls.showDc && req.dc != null && <span className="roll-dc">DC {req.dc}</span>}
              <span className="roll-prompt-desc">{req.description}</span>
              {resolved && (
                <span className="roll-modifier">{formatMod(resolved.modifier)}</span>
              )}
              {isHallucination && (
                <span className="roll-warning">Not on character sheet</span>
              )}
            </div>
            <div className="roll-actions">
              {resolved ? (
                <>
                  <button
                    className={`roll-btn roll-d20 ${value != null ? 'roll-done' : ''}`}
                    onClick={() => handleRollD20(i)}
                    disabled={value != null}
                  >
                    {value != null ? `Rolled: ${value}` : `Roll (${formatMod(resolved.modifier)})`}
                  </button>
                  {req.take_10_eligible && req.take_10_value != null && value == null && (
                    <button
                      className="roll-btn roll-take"
                      onClick={() => onRollValueChange(i, req.take_10_value!, 'take_10')}
                    >
                      Take 10 (= {req.take_10_value})
                    </button>
                  )}
                  {req.take_20_eligible && req.take_20_value != null && value == null && (
                    <button
                      className="roll-btn roll-take"
                      onClick={() => onRollValueChange(i, req.take_20_value!, 'take_20')}
                    >
                      Take 20 (= {req.take_20_value})
                    </button>
                  )}
                </>
              ) : (
                <input
                  ref={i === 0 ? rollInputRef : undefined}
                  type="number"
                  min="-100"
                  max="100"
                  placeholder="Roll result"
                  value={value ?? ''}
                  onChange={e => handleManualRollChange(i, e.target.value)}
                  onKeyDown={e => {
                    if (e.key === 'Enter' && allRollsFilled) onSubmit()
                  }}
                  className="roll-input"
                />
              )}
            </div>
          </div>
        )
      })}
      <button
        onClick={onSubmit}
        disabled={!allRollsFilled}
        className="roll-submit-btn"
      >
        Submit {pendingRolls.entries.length > 1 ? 'All Rolls' : 'Roll'}
      </button>
    </div>
  )
}

export default PendingRollsPanel
