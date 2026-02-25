import { useEffect, useCallback } from 'react'
import { DiceRollResult } from '../../rules/dice'
import './RollResultModal.scss'

export interface RollResultDisplay {
  /** e.g. "Attack Roll", "Perception Check", "STR Check" */
  label: string
  /** The dice result */
  result: DiceRollResult
  /** Optional breakdown text, e.g. "BAB +1" */
  modifierLabel?: string
}

interface RollResultModalProps {
  roll: RollResultDisplay | null
  onClose: () => void
}

export const RollResultModal = ({ roll, onClose }: RollResultModalProps) => {
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape') onClose()
  }, [onClose])

  useEffect(() => {
    if (roll) {
      document.addEventListener('keydown', handleKeyDown)
      return () => document.removeEventListener('keydown', handleKeyDown)
    }
  }, [roll, handleKeyDown])

  if (!roll) return null

  const { label, result, modifierLabel } = roll
  const { natural, modifier, total, isCritical, isFumble } = result

  const formatMod = (m: number) => (m >= 0 ? `+${m}` : `${m}`)

  let resultClass = ''
  let resultNote = ''
  if (isCritical) {
    resultClass = 'crit'
    resultNote = 'Natural 20!'
  } else if (isFumble) {
    resultClass = 'fumble'
    resultNote = 'Natural 1!'
  }

  return (
    <div className="roll-modal-overlay" onClick={onClose}>
      <div
        className={`roll-modal ${resultClass}`}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-label="Dice roll result"
      >
        <div className="roll-modal-header">
          <span className="roll-label">{label}</span>
          <button className="roll-close" onClick={onClose} aria-label="Close">✕</button>
        </div>

        <div className="roll-modal-body">
          <div className="dice-display">
            <span className="dice-icon">🎲</span>
            <span className={`dice-natural ${resultClass}`}>{natural}</span>
          </div>

          <div className="roll-breakdown">
            <span className="breakdown-part">d20: {natural}</span>
            <span className="breakdown-part">
              {modifierLabel || 'Modifier'}: {formatMod(modifier)}
            </span>
          </div>

          <div className={`roll-total ${resultClass}`}>
            <span className="total-label">Total</span>
            <span className="total-value">{total}</span>
          </div>

          {resultNote && (
            <div className={`roll-note ${resultClass}`}>{resultNote}</div>
          )}
        </div>
      </div>
    </div>
  )
}

export default RollResultModal
