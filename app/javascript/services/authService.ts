import { API_ROUTES } from '../constants/apiRoutes'
import { apiFetch } from '../utils/api'
import type { AuthUser, CurrentUserResponse } from '../types/auth'

export async function fetchCurrentUser(): Promise<AuthUser | null> {
  const payload = await apiFetch<CurrentUserResponse>(API_ROUTES.currentUser, {
    method: 'GET',
    credentials: 'same-origin',
  })
  return payload.user
}
