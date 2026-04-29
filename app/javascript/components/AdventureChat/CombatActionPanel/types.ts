import type { CombatDiceStrategy } from '../../../types/auth'

export interface CombatActionPanelProps {
  adventureId: number
  diceStrategy: CombatDiceStrategy
  onDiceStrategyChange: (next: CombatDiceStrategy) => void
  onCombatContextUpdate?: (combatContext: Record<string, unknown> | null) => void
  externalCombatContext?: Record<string, unknown> | null
}

export interface ResolvedEntry {
  id: string
  message: string
  hit: boolean
  target_dropped: boolean
}

export interface ParsedDiceExpression {
  count: number
  sides: number
  mod: number
}

// Loose shapes used by entry-builder helpers — the canonical wire types
// live in services/combatActionService; these aliases just narrow them
// to the fields the helpers actually read.
export interface AooEvent {
  message: string
  hit: boolean
  target_dropped: boolean
}

export interface NpcEvent {
  kind: string
  creature_name: string
  message?: string
  outcome?: { hit?: boolean; target_dropped?: boolean; message?: string }
}
