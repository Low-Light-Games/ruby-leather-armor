import { useEffect, useState } from 'react'
import CombatActionEconomyChips from '../AdventureChat/CombatActionEconomyChips'
import CombatActionPanel from '../AdventureChat/CombatActionPanel'
import type { CombatDiceStrategy } from '../../types/auth'

interface Props {
  adventureId: number
  combatContext: Record<string, unknown> | null
  diceStrategy: CombatDiceStrategy
  onDiceStrategyChange: (next: CombatDiceStrategy) => void
  onCombatEnded?: () => void
}

/**
 * Center-column combat HUD lifted out of AdventureChat so the message
 * log can move to the right column during combat (PR-J playtest
 * feedback — too much UI in one stack on average screens).
 *
 * Owns the local liveCombatContext so the action-economy chips can
 * refresh immediately after each resolved action without waiting for
 * the parent adventure record to refetch. When the panel reports a
 * context whose .active flipped to false (last NPC down, player
 * death), bubble it via onCombatEnded so AdventurePlay can refetch
 * the adventure and tear down the combat layout — otherwise the
 * parent's stale combat_context keeps showCombatHud true.
 */
export const CombatHud = ({ adventureId, combatContext, diceStrategy, onDiceStrategyChange, onCombatEnded }: Props) => {
  const [liveCombatContext, setLiveCombatContext] = useState<Record<string, unknown> | null>(combatContext)

  useEffect(() => {
    setLiveCombatContext(combatContext)
  }, [combatContext])

  const handleCombatContextUpdate = (next: Record<string, unknown> | null) => {
    setLiveCombatContext(next)
    if (next && next.active === false) onCombatEnded?.()
  }

  return (
    <div className="combat-hud">
      <CombatActionEconomyChips combatContext={liveCombatContext} />
      <CombatActionPanel
        adventureId={adventureId}
        diceStrategy={diceStrategy}
        onDiceStrategyChange={onDiceStrategyChange}
        onCombatContextUpdate={handleCombatContextUpdate}
        externalCombatContext={combatContext}
      />
    </div>
  )
}

export default CombatHud
