import { apiFetch } from '../utils/api'
import type { CombatDiceStrategy } from '../types/auth'
import type { BattlefieldSnapshot } from '../types'

export interface CombatTarget {
  actor_sheet_id: number
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

export interface CombatBuffOption {
  id: string
  label: string
  source_type: string
  source_id: string | number
  duration: string | null
  summary: string | null
  action_cost: string
}

export interface CombatHealOption {
  id: string
  label: string
  source_type: string
  source_id: string | number
  dice: string
  summary: string | null
  action_cost: string
}

export interface CombatActionOptionsResponse {
  attack_options: CombatAttackOption[]
  buff_options: CombatBuffOption[]
  heal_options: CombatHealOption[]
  targets: CombatTarget[]
  action_economy: CombatActionEconomy | null
  dice_strategy: CombatDiceStrategy
  battlefield: BattlefieldSnapshot | null
  player_position: { x: number; y: number } | null
  player_speed_squares: number
}

export interface CombatAttackResult {
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

export interface NpcTurnEvent {
  kind: 'npc_attack' | 'npc_move' | 'npc_flee' | 'npc_skip'
  creature_id: number | null
  creature_name: string
  message?: string
  outcome?: AoOOutcome
  from?: { x: number; y: number }
  to?: { x: number; y: number }
}

export interface CombatEndTurnResult {
  kind: 'end_turn'
  round_advanced_to: number
  npc_events: NpcTurnEvent[]
  message: string
}

export interface AoOOutcome {
  attacker_name: string
  target_name: string
  hit: boolean
  natural: number
  total: number
  defense_dc: number
  damage_total: number | null
  damage_type: string | null
  target_hp_before: number
  target_hp_after: number
  target_dropped: boolean
  weapon_label: string
  message: string
}

export interface CombatMoveResult {
  kind: 'move'
  from: { x: number; y: number }
  to: { x: number; y: number }
  distance_squares: number
  movement_mode: string
  battlefield_version: number | null
  attacks_of_opportunity: AoOOutcome[]
  message: string
}

export interface CombatBuffResult {
  kind: 'buff'
  spell_id: string
  spell_name: string
  duration: string | null
  summary: string | null
  action_cost: string
  message: string
}

export interface CombatHealResult {
  kind: 'heal'
  spell_id: string
  spell_name: string
  dice: string
  rolled: number
  healed: number
  hp_before: number
  hp_after: number
  action_cost: string
  message: string
}

export interface CombatAttackResolved {
  status: 'resolved'
  result: CombatAttackResult | CombatEndTurnResult | CombatMoveResult | CombatBuffResult | CombatHealResult
  combat_context: Record<string, unknown> | null
}

export interface CombatAttackPending {
  status: 'awaiting_player_dice'
  request: {
    kind: 'attack'
    attack_option_id: string
    attack_label: string
    target_name: string
    target_actor_sheet_id: number
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
  target_actor_sheet_id: number
  submitted_dice?: { attack_natural: number; damage_natural: number }
}

export interface CombatEndTurnBody {
  kind: 'end_turn'
}

export interface CombatMoveBody {
  kind: 'move'
  x: number
  y: number
  withdraw?: boolean
}

export interface CombatBuffBody {
  kind: 'buff'
  spell_id: string
}

export interface CombatHealBody {
  kind: 'heal'
  spell_id: string
}

export type CombatActionBody =
  | CombatAttackBody
  | CombatEndTurnBody
  | CombatMoveBody
  | CombatBuffBody
  | CombatHealBody

export async function fetchCombatActionOptions(adventureId: number): Promise<CombatActionOptionsResponse> {
  return apiFetch(`/adventures/${adventureId}/combat_action/options`, { method: 'GET', credentials: 'same-origin' })
}

export async function postCombatAction(adventureId: number, body: CombatActionBody): Promise<CombatAttackResponse> {
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
