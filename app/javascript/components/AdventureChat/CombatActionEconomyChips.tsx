import { useMemo } from 'react'

export interface ActionEconomyShape {
  round?: number | null
  holder?: string | null
  standard_available?: boolean
  move_available?: boolean
  swift_available?: boolean
  full_round_claimed?: boolean
}

interface Props {
  combatContext: Record<string, unknown> | null
}

interface Chip {
  key: 'standard' | 'move' | 'swift' | 'free'
  label: string
  available: boolean
  tooltip: string
}

function readEconomy(combatContext: Record<string, unknown> | null): ActionEconomyShape | null {
  if (!combatContext) return null
  const econ = combatContext.action_economy
  if (!econ || typeof econ !== 'object') return null
  return econ as ActionEconomyShape
}

const STANDARD_TOOLTIP = 'Standard action — most attacks, casting most spells, full attacks consume this plus your move.'
const MOVE_TOOLTIP = 'Move action — moving up to your speed, drawing a weapon, standing up, retrieving a stowed item.'
const SWIFT_TOOLTIP = 'Swift action — quickened spells, certain class features. One per turn.'
const FREE_TOOLTIP = 'Free actions — speaking, dropping an item. No limit per turn (within reason).'

export const CombatActionEconomyChips = ({ combatContext }: Props) => {
  const economy = readEconomy(combatContext)

  const chips: Chip[] | null = useMemo(() => {
    if (!economy) return null
    return [
      {
        key: 'standard',
        label: 'Standard',
        available: economy.standard_available !== false,
        tooltip: STANDARD_TOOLTIP,
      },
      {
        key: 'move',
        label: 'Move',
        available: economy.move_available !== false,
        tooltip: MOVE_TOOLTIP,
      },
      {
        key: 'swift',
        label: 'Swift',
        available: economy.swift_available !== false,
        tooltip: SWIFT_TOOLTIP,
      },
      {
        key: 'free',
        label: 'Free',
        available: true,
        tooltip: FREE_TOOLTIP,
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
