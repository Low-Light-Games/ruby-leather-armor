import { apiFetch } from '../utils/api'
import type { CombatDiceStrategy } from '../types/auth'

export interface CombatTarget {
  creature_sheet_id: number
  name: string
  hp: number
  max_hp: number
  dropped: boolean
}

export interface CombatAttackOption {
  id: string
  label: string
  attack_mode: string
  defense_kind: string
  source_type: string
  source_id?: number | string
  damage: string
  damage_type?: string | null
  action_cost: string
}

export interface CombatActionEconomy {
  round?: number | null
  holder?: string | null
  standard_available?: boolean
  move_available?: boolean
  swift_available?: boolean
  full_round_claimed?: boolean
}

export interface CombatActionOptionsResponse {
  attack_options: CombatAttackOption[]
  targets: CombatTarget[]
  action_economy: CombatActionEconomy | null
  dice_strategy: CombatDiceStrategy
}

export interface CombatAttackResolved {
  status: 'resolved'
  result: {
    kind: 'attack'
    attack_option_id: string
    attack_label: string
    target_name: string
    attack_mode: string
    defense_kind: string
    attack_bonus: number
    attack_natural: number
    attack_total: number
    defense_dc: number
    crit_threat: boolean
    natural_one: boolean
    hit: boolean
    damage_expression: string | null
    damage_type: string | null
    damage_natural: number | null
    damage_total: number | null
    target_hp_before: number
    target_hp_after: number
    target_dropped: boolean
    message: string
  }
  combat_context: Record<string, unknown> | null
}

export interface CombatAttackPending {
  status: 'awaiting_player_dice'
  request: {
    kind: 'attack'
    attack_option_id: string
    attack_label: string
    target_name: string
    target_creature_sheet_id: number
    attack_bonus: number
    defense_dc: number
    defense_kind: string
    damage_expression: string
    damage_type: string | null
    damage_ability_bonus: number
  }
  combat_context: Record<string, unknown> | null
}

export type CombatAttackResponse = CombatAttackResolved | CombatAttackPending

export interface CombatAttackBody {
  kind: 'attack'
  attack_option_id: string
  target_creature_sheet_id: number
  submitted_dice?: { attack_natural: number; damage_natural: number }
}

export async function fetchCombatActionOptions(adventureId: number): Promise<CombatActionOptionsResponse> {
  return apiFetch(`/adventures/${adventureId}/combat_action/options`, { method: 'GET', credentials: 'same-origin' })
}

export async function postCombatAction(adventureId: number, body: CombatAttackBody): Promise<CombatAttackResponse> {
  return apiFetch(`/adventures/${adventureId}/combat_action`, {
    method: 'POST',
    credentials: 'same-origin',
    body: JSON.stringify(body),
  })
}

export async function setCombatDiceStrategy(strategy: CombatDiceStrategy): Promise<{ combat_dice_strategy: CombatDiceStrategy }> {
  return apiFetch('/user_preferences', {
    method: 'PATCH',
    credentials: 'same-origin',
    body: JSON.stringify({ combat_dice_strategy: strategy }),
  })
}
