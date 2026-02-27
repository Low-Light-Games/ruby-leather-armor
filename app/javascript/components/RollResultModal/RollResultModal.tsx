import { useEffect, useCallback } from 'react'
import type { DiceRollResult, DamageRollResult } from '../../rules/dice'
import { formatMod } from '../../utils/formatting'
import './RollResultModal.scss'

export interface RollResultDisplay {
  label: string
  result: DiceRollResult
  modifierLabel?: string
}

interface RollResultModalProps {
  roll: RollResultDisplay | null
  damageRoll?: DamageRollResult | null
  onClose: () => void
}

export const RollResultModal = ({ roll, damageRoll, onClose }: RollResultModalProps) => {
  const visible = !!roll || !!damageRoll

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape') onClose()
  }, [onClose])

  useEffect(() => {
    if (visible) {
      document.addEventListener('keydown', handleKeyDown)
      return () => document.removeEventListener('keydown', handleKeyDown)
    }
  }, [visible, handleKeyDown])

  if (!visible) return null

  if (damageRoll) return <DamageModal damage={damageRoll} onClose={onClose} />
  if (roll) return <D20Modal roll={roll} onClose={onClose} />
  return null
}

// ── d20 roll modal (existing) ────────────────────────────────

function D20Modal({ roll, onClose }: { roll: RollResultDisplay; onClose: () => void }) {
  const { label, result, modifierLabel } = roll
  const { natural, modifier, total, isCritical, isFumble } = result

  let resultClass = ''
  let resultNote = ''
  if (isCritical) { resultClass = 'crit'; resultNote = 'Natural 20!' }
  else if (isFumble) { resultClass = 'fumble'; resultNote = 'Natural 1!' }

  return (
    <div className="roll-modal-overlay" onClick={onClose}>
      <div className={`roll-modal ${resultClass}`} onClick={e => e.stopPropagation()} role="dialog" aria-label="Dice roll result">
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
            <span className="breakdown-part">{modifierLabel || 'Modifier'}: {formatMod(modifier)}</span>
          </div>
          <div className={`roll-total ${resultClass}`}>
            <span className="total-label">Total</span>
            <span className="total-value">{total}</span>
          </div>
          {resultNote && <div className={`roll-note ${resultClass}`}>{resultNote}</div>}
        </div>
      </div>
    </div>
  )
}

// ── Damage roll modal ────────────────────────────────────────

function DamageModal({ damage, onClose }: { damage: DamageRollResult; onClose: () => void }) {
  const { label, rolls, diceNotation, flatBonus, bonusBreakdown, total, damageType } = damage

  return (
    <div className="roll-modal-overlay" onClick={onClose}>
      <div className="roll-modal damage" onClick={e => e.stopPropagation()} role="dialog" aria-label="Damage roll result">
        <div className="roll-modal-header">
          <span className="roll-label">{label}</span>
          <button className="roll-close" onClick={onClose} aria-label="Close">✕</button>
        </div>
        <div className="roll-modal-body">
          <div className="dice-display">
            <span className="dice-icon">🎲</span>
            <span className="dice-notation">{diceNotation}</span>
          </div>

          <div className="damage-dice-pills">
            {rolls.map((r, i) => (
              <span key={i} className="dice-pill">{r}</span>
            ))}
            {flatBonus !== 0 && (
              <span className="dice-pill flat">{flatBonus > 0 ? `+${flatBonus}` : flatBonus}</span>
            )}
          </div>

          {bonusBreakdown.length > 0 && (
            <div className="damage-breakdown">
              {bonusBreakdown.map((part, i) => (
                <span key={i} className="breakdown-part">{part}</span>
              ))}
            </div>
          )}

          <div className="roll-total damage">
            <span className="total-value">{total}</span>
            <span className="damage-type-badge">{damageType}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default RollResultModal
