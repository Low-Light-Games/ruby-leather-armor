import { useEffect, useState } from 'react'
import CombatActionEconomyChips from '../AdventureChat/CombatActionEconomyChips'
import CombatActionPanel from '../AdventureChat/CombatActionPanel'
import type { CombatHudProps } from '../../types'

export const CombatHud = ({ adventureId, combatContext, diceStrategy, onDiceStrategyChange, onCombatEnded }: CombatHudProps) => {
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
