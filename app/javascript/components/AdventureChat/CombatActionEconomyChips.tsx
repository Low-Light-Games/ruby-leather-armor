import { useMemo } from 'react'
import type { ActionEconomyChip, ActionEconomyShape, CombatActionEconomyChipsProps } from '../../types'
import {
  ACTION_ECONOMY_FREE_TOOLTIP,
  ACTION_ECONOMY_MOVE_TOOLTIP,
  ACTION_ECONOMY_STANDARD_TOOLTIP,
  ACTION_ECONOMY_SWIFT_TOOLTIP,
} from './CombatActionEconomyChips.constants'
import './CombatActionEconomyChips.scss'

function readActionEconomy(combatContext: Record<string, unknown> | null): ActionEconomyShape | null {
  if (!combatContext) return null
  const econ = combatContext.action_economy
  if (!econ || typeof econ !== 'object') return null
  return econ as ActionEconomyShape
}

export const CombatActionEconomyChips = ({ combatContext }: CombatActionEconomyChipsProps) => {
  const economy = readActionEconomy(combatContext)

  const chips: ActionEconomyChip[] | null = useMemo(() => {
    if (!economy) return null
    return [
      {
        key: 'standard',
        label: 'Standard',
        available: economy.standard_available !== false,
        tooltip: ACTION_ECONOMY_STANDARD_TOOLTIP,
      },
      {
        key: 'move',
        label: 'Move',
        available: economy.move_available !== false,
        tooltip: ACTION_ECONOMY_MOVE_TOOLTIP,
      },
      {
        key: 'swift',
        label: 'Swift',
        available: economy.swift_available !== false,
        tooltip: ACTION_ECONOMY_SWIFT_TOOLTIP,
      },
      {
        key: 'free',
        label: 'Free',
        available: true,
        tooltip: ACTION_ECONOMY_FREE_TOOLTIP,
      },
    ]
  }, [economy])

  if (!chips) return null

  return (
    <div className="combat-action-economy" aria-label="Action economy">
      {chips.map(chip => (
        <span
          key={chip.key}
          className={`action-economy-chip${chip.available ? ' available' : ' spent'}`}
          title={chip.tooltip}
          aria-label={`${chip.label}: ${chip.available ? 'available' : 'spent'}`}
        >
          <span className="chip-dot" aria-hidden="true">
            {chip.key === 'free' ? '∞' : chip.available ? '●' : '○'}
          </span>
          <span className="chip-label">{chip.label}</span>
        </span>
      ))}
    </div>
  )
}

export default CombatActionEconomyChips
