import { API_ROUTES } from '../constants/apiRoutes'
import { apiFetch } from '../utils/api'
import type { AuthUser, CurrentUserResponse } from '../types/auth'

export async function fetchCurrentUser(): Promise<AuthUser | null> {
  const payload = await apiFetch<CurrentUserResponse>(API_ROUTES.currentUser, {
    method: 'GET',
    credentials: 'same-origin',
  })

  const redditTracker = (window as Window & { rdt?: (...args: string[]) => void }).rdt
  if (payload.oauth_new_signup && typeof redditTracker === 'function') {
    redditTracker('track', 'SignUp')
  }

  return payload.user
}
