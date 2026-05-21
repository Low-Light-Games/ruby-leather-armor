export type UsageSnapshotKind = 'monthly' | 'guest_lifetime'

export interface UsageSnapshot {
  kind: UsageSnapshotKind
  current_tokens: number
  limit_tokens: number | null
  percentage: number
  limit_reached: boolean
  delinquent: boolean
  grace_period_ends_at: string | null
}

export type CombatDiceStrategy = 'client' | 'server'

export interface AuthUser {
  id: number
  email: string
  handle: string | null
  placeholder_email: boolean
  admin: boolean
  guest: boolean
  email_verified: boolean
  email_verification_required: boolean
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
  oauth_new_signup?: boolean
  email_prompt?: boolean
}

export interface SignupPayload {
  email: string
  handle?: string
  password: string
  passwordConfirmation: string
}
