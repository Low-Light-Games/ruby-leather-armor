import { useEffect, useState } from 'react'
import CombatActionEconomyChips from '../AdventureChat/CombatActionEconomyChips'
import CombatActionPanel from '../AdventureChat/CombatActionPanel'
import type { CombatDiceStrategy } from '../../types/auth'

interface Props {
  adventureId: number
  combatContext: Record<string, unknown> | null
  diceStrategy: CombatDiceStrategy
  onDiceStrategyChange: (next: CombatDiceStrategy) => void
}

/**
 * Center-column combat HUD lifted out of AdventureChat so the message
 * log can move to the right column during combat (PR-J playtest
 * feedback — too much UI in one stack on average screens).
 *
 * Owns the local liveCombatContext so the action-economy chips can
 * refresh immediately after each resolved action without waiting for
 * the parent adventure record to refetch.
 */
export const CombatHud = ({ adventureId, combatContext, diceStrategy, onDiceStrategyChange }: Props) => {
  const [liveCombatContext, setLiveCombatContext] = useState<Record<string, unknown> | null>(combatContext)

  useEffect(() => {
    setLiveCombatContext(combatContext)
  }, [combatContext])

  return (
    <div className="combat-hud">
      <CombatActionEconomyChips combatContext={liveCombatContext} />
      <CombatActionPanel
        adventureId={adventureId}
        diceStrategy={diceStrategy}
        onDiceStrategyChange={onDiceStrategyChange}
        onCombatContextUpdate={setLiveCombatContext}
      />
    </div>
  )
}

export default CombatHud
