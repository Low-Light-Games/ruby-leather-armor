import { useCallback, useEffect, useState } from 'react'
import {
  fetchCombatActionOptions,
  postCombatAction,
  setCombatDiceStrategy,
  type CombatActionOptionsResponse,
  type CombatAttackOption,
  type CombatAttackPending,
  type CombatAttackResolved,
  type CombatAttackResponse,
  type CombatTarget,
} from '../../../services/combatActionService'
import type { CombatDiceStrategy } from '../../../types/auth'
import { rollD20 } from '../../../rules/dice'
import CombatGrid from '../CombatGrid'
import {
  describeAttackOption,
  entriesForAttackOfOpportunity,
  entriesForNpcEvent,
  makeResolvedEntry,
  pickAliveTargetId,
  rollDamageExpression,
} from './helpers'
import type { CombatActionPanelProps, ResolvedEntry } from './types'
import './CombatActionPanel.scss'

export const CombatActionPanel = ({
  adventureId,
  externalCombatContext,
  diceStrategy,
  onDiceStrategyChange,
  onCombatContextUpdate,
}: CombatActionPanelProps) => {
  const [options, setOptions] = useState<CombatActionOptionsResponse | null>(null)
  const [loading, setLoading] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selectedTargetId, setSelectedTargetId] = useState<number | null>(null)
  const [history, setHistory] = useState<ResolvedEntry[]>([])
  const [pending, setPending] = useState<CombatAttackPending['request'] | null>(null)
  const [withdrawMode, setWithdrawMode] = useState(false)

  const refreshCombatTargetOptions = useCallback(async () => {
    setLoading(true)
    try {
      const data = await fetchCombatActionOptions(adventureId)
      setOptions(data)
      setError(null)
      setSelectedTargetId(prev => pickAliveTargetId(data.targets, prev))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setLoading(false)
    }
  }, [adventureId])

  useEffect(() => {
    void refreshCombatTargetOptions()
  }, [refreshCombatTargetOptions])

  // Internal HUD actions update CombatHud's local mirror only — they don't
  // change the parent prop — so refetching on this signal won't double-fire
  // on every attack/move.
  const externalEconomySignal = externalCombatContext
    ? JSON.stringify((externalCombatContext as { action_economy?: unknown }).action_economy ?? null)
    : null
  useEffect(() => {
    if (externalEconomySignal === null) return
    void refreshCombatTargetOptions()
  }, [externalEconomySignal, refreshCombatTargetOptions])

  const recordResolution = useCallback(
    (resolved: CombatAttackResolved) => {
      const result = resolved.result
      const isAttack = result.kind === 'attack'
      const entries: ResolvedEntry[] = [
        makeResolvedEntry('main', result.message,
          isAttack ? result.hit : true,
          isAttack ? result.target_dropped : false),
      ]
      if (result.kind === 'move') {
        result.attacks_of_opportunity.forEach((aoo, i) => entries.push(entriesForAttackOfOpportunity(aoo, i)))
      }
      if (result.kind === 'end_turn') {
        result.npc_events.forEach((evt, i) => entries.push(entriesForNpcEvent(evt, i)))
      }
      setHistory(prev => [...prev, ...entries])
      onCombatContextUpdate?.(resolved.combat_context)
    },
    [onCombatContextUpdate],
  )

  const handleResponse = useCallback(
    (response: CombatAttackResponse) => {
      if (response.status === 'resolved') {
        recordResolution(response)
        setPending(null)
      } else {
        setPending(response.request)
      }
    },
    [recordResolution],
  )

  const handleMove = async (x: number, y: number) => {
    setSubmitting(true)
    setError(null)
    try {
      const body: { kind: 'move'; x: number; y: number; withdraw?: boolean } = { kind: 'move', x, y }
      if (withdrawMode) body.withdraw = true
      const response = await postCombatAction(adventureId, body)
      handleResponse(response)
      setWithdrawMode(false)
      await refreshCombatTargetOptions()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setSubmitting(false)
    }
  }

  const handleEndTurn = async () => {
    setSubmitting(true)
    setError(null)
    try {
      const response = await postCombatAction(adventureId, { kind: 'end_turn' })
      handleResponse(response)
      await refreshCombatTargetOptions()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setSubmitting(false)
    }
  }

  const handleAttack = async (option: CombatAttackOption, target: CombatTarget) => {
    setSubmitting(true)
    setError(null)
    try {
      const response = await postCombatAction(adventureId, {
        kind: 'attack',
        attack_option_id: option.id,
        target_creature_sheet_id: target.creature_sheet_id,
      })
      handleResponse(response)
      await refreshCombatTargetOptions()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setSubmitting(false)
    }
  }

  const handleSubmitClientDice = async () => {
    if (!pending) return
    setSubmitting(true)
    setError(null)
    try {
      const attack = rollD20(0)
      const damage = rollDamageExpression(pending.damage_expression)
      const response = await postCombatAction(adventureId, {
        kind: 'attack',
        attack_option_id: pending.attack_option_id,
        target_creature_sheet_id: pending.target_creature_sheet_id,
        submitted_dice: { attack_natural: attack.natural, damage_natural: damage },
      })
      handleResponse(response)
      await refreshCombatTargetOptions()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setSubmitting(false)
    }
  }

  const handleDiceStrategyToggle = async () => {
    const next: CombatDiceStrategy = diceStrategy === 'client' ? 'server' : 'client'
    try {
      await setCombatDiceStrategy(next)
      onDiceStrategyChange(next)
      setOptions(prev => (prev ? { ...prev, dice_strategy: next } : prev))
      setPending(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  if (loading && !options) {
    return <div className="combat-action-panel loading">Loading combat actions…</div>
  }
  if (!options) return null

  const target = selectedTargetId != null
    ? options.targets.find(t => t.creature_sheet_id === selectedTargetId) || null
    : null
  const aliveTargets = options.targets.filter(t => !t.dropped)
  const noActions = options.attack_options.length === 0

  return (
    <div className="combat-action-panel">
      <div className="combat-action-panel-header">
        <span className="panel-title">Your Turn</span>
        <button
          type="button"
          className={`dice-strategy-toggle ${diceStrategy}`}
          onClick={handleDiceStrategyToggle}
          title={diceStrategy === 'server' ? 'Server is rolling for you. Click to roll dice yourself.' : "You're rolling. Click to let the server roll instantly."}
        >
          {diceStrategy === 'server' ? '⚄ Auto-roll' : '🎲 Self-roll'}
        </button>
      </div>

      {options.battlefield && (
        <CombatGrid
          battlefield={options.battlefield}
          playerPosition={options.player_position}
          speedSquares={options.player_speed_squares}
          canMove={options.action_economy?.move_available !== false && pending === null}
          canWithdraw={
            options.action_economy?.standard_available !== false &&
            options.action_economy?.move_available !== false &&
            options.action_economy?.full_round_claimed !== true &&
            pending === null
          }
          withdrawMode={withdrawMode}
          onWithdrawToggle={() => setWithdrawMode(prev => !prev)}
          onSquareClick={handleMove}
          busy={submitting}
          targets={options.targets}
        />
      )}

      {aliveTargets.length > 0 && (
        <div className="target-row">
          <label htmlFor="combat-target">Target:</label>
          <select
            id="combat-target"
            value={selectedTargetId ?? ''}
            onChange={e => setSelectedTargetId(e.target.value ? parseInt(e.target.value, 10) : null)}
            disabled={submitting}
          >
            {aliveTargets.map(t => (
              <option key={t.creature_sheet_id} value={t.creature_sheet_id}>
                {t.name} ({t.hp}/{t.max_hp} HP)
              </option>
            ))}
          </select>
        </div>
      )}

      {noActions ? (
        <div className="panel-empty">No attack actions available — your standard action is spent.</div>
      ) : (
        <div className="attack-options">
          {options.attack_options.map(option => (
            <button
              key={option.id}
              type="button"
              className="attack-option-btn"
              disabled={submitting || pending !== null || target === null}
              onClick={() => target && handleAttack(option, target)}
              title={describeAttackOption(option)}
            >
              <span className="attack-label">{option.label}</span>
              <span className="attack-damage">{option.damage}{option.damage_type ? ` ${option.damage_type}` : ''}</span>
            </button>
          ))}
        </div>
      )}

      {pending && (
        <div className="pending-self-roll">
          <div>
            <strong>{pending.attack_label}</strong> vs <strong>{pending.target_name}</strong>:
            need {pending.attack_bonus >= 0 ? '+' : ''}{pending.attack_bonus} to hit AC {pending.defense_dc}.
          </div>
          <button
            type="button"
            className="self-roll-btn"
            disabled={submitting}
            onClick={handleSubmitClientDice}
          >
            🎲 Roll attack + damage
          </button>
        </div>
      )}

      <div className="end-turn-row">
        <button
          type="button"
          className="end-turn-btn"
          disabled={submitting || pending !== null}
          onClick={handleEndTurn}
          title="End your turn — advances the round and refreshes your action economy."
        >
          End Turn ⏭
        </button>
      </div>

      {history.length > 0 && (
        <ul className="combat-action-log">
          {history.slice(-3).map(entry => (
            <li key={entry.id} className={`log-entry ${entry.hit ? 'hit' : 'miss'}${entry.target_dropped ? ' dropped' : ''}`}>
              {entry.message}
            </li>
          ))}
        </ul>
      )}

      {error && <div className="combat-action-error" role="alert">{error}</div>}
    </div>
  )
}

export default CombatActionPanel
