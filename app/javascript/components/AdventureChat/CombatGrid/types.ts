import type { BattlefieldSnapshot } from '../../../types'
import type { CombatTarget } from '../../../services/combatActionService'

export interface CombatGridProps {
  battlefield: BattlefieldSnapshot
  playerPosition: { x: number; y: number } | null
  speedSquares: number
  canMove: boolean
  canWithdraw: boolean
  withdrawMode: boolean
  onWithdrawToggle: () => void
  onSquareClick: (x: number, y: number) => void
  busy: boolean
  targets?: CombatTarget[]
}

export interface ResolvedToken {
  id: string
  label: string
  displayLabel: string
  x: number
  y: number
  type: string
  creatureSheetId: number | null
  isPlayer: boolean
}

export interface ViewportRect {
  minX: number
  minY: number
  width: number
  height: number
}
