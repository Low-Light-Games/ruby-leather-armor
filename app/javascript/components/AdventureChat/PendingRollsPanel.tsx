import { useRef, useEffect } from 'react'
import type { AdventureSheet, DerivedStats } from '../../types'
import { formatMod } from '../../utils/formatting'
import { rollD20 } from '../../rules/dice'
import type { DamageRollResult } from '../../rules/dice'
import { rollSpellDamage, rollUnarmedDamage, rollWeaponDamage } from '../../rules/damage'
import { getSpellById } from '../../rules/pathfinder_spells'
import type { RollResultDisplay } from '../RollResultModal'
import { rollLabel, PendingRolls, ResolutionMethod } from './rollHelpers'

interface PendingRollsPanelProps {
  pendingRolls: PendingRolls
  derivedStats?: DerivedStats | null
  adventureSheet?: AdventureSheet | null
  onRollValueChange: (index: number, value: number, method: ResolutionMethod) => void
  onSubmit: () => void
  allRollsFilled: boolean
  onRollModal: (index: number, display: RollResultDisplay) => void
  onDamageRollModal: (index: number, damage: DamageRollResult) => void
}

const PendingRollsPanel = ({
  pendingRolls, derivedStats, adventureSheet,
  onRollValueChange, onSubmit, allRollsFilled, onRollModal,
  onDamageRollModal,
}: PendingRollsPanelProps) => {
  const rollInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    rollInputRef.current?.focus()
  }, [])

  const handleRollD20 = (index: number) => {
    const entry = pendingRolls.entries[index]
    if (!entry.resolved || entry.resolved.kind !== 'd20') return

    const result = rollD20(entry.resolved.modifier)
    onRollModal(index, {
      label: entry.resolved.label,
      result,
      modifierLabel: entry.resolved.modifierLabel,
    })
  }

  const handleQuickDamageRoll = (index: number) => {
    const entry = pendingRolls.entries[index]
    const resolved = entry.resolved
    if (!resolved || !derivedStats || !adventureSheet) return

    let damageResult: DamageRollResult | null = null

    if (resolved.kind === 'spell_damage') {
      const spell = getSpellById(resolved.spellId)
      if (!spell) return

      damageResult = rollSpellDamage(spell, adventureSheet.level)
    } else if (resolved.kind === 'weapon_damage') {
      damageResult = rollWeaponDamage(resolved.itemId, adventureSheet, derivedStats)
    } else if (resolved.kind === 'unarmed_damage') {
      damageResult = rollUnarmedDamage(adventureSheet, derivedStats)
    }

    if (!damageResult) return
    onDamageRollModal(index, damageResult)
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
              {resolved?.kind === 'd20' && (
                <span className="roll-modifier">{formatMod(resolved.modifier)}</span>
              )}
              {isHallucination && (
                <span className="roll-warning">Not on character sheet</span>
              )}
            </div>
            <div className="roll-actions">
              {resolved ? (
                <>
                  {resolved.kind === 'd20' ? (
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
                    <button
                      className={`roll-btn roll-d20 ${value != null ? 'roll-done' : ''}`}
                      onClick={() => handleQuickDamageRoll(i)}
                      disabled={value != null}
                    >
                      {value != null ? `Rolled: ${value}` : 'Roll Damage'}
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
