import type { AuthUser } from '../types/auth'

export const canAccessPaidAdventureOptions = (user: AuthUser): boolean =>
  user.admin || user.plan_key !== 'free'
