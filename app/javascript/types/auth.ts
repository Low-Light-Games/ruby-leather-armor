export interface UsageSnapshot {
  current_tokens: number
  limit_tokens: number
  percentage: number
  limit_reached: boolean
  delinquent: boolean
  grace_period_ends_at: string | null
}

export type CombatDiceStrategy = 'client' | 'server'

export interface AuthUser {
  id: number
  email: string
  admin: boolean
  plan_key: string
  has_billing_profile: boolean
  onboarding_state: 'new' | 'in_progress' | 'completed'
  banned: boolean
  trusted: boolean
  moderation_strikes: number
  combat_dice_strategy: CombatDiceStrategy
  usage: UsageSnapshot
}

export interface CurrentUserResponse {
  user: AuthUser | null
}
