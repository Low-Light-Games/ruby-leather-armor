import { API_ROUTES } from '../constants/apiRoutes'
import { apiFetch } from '../utils/api'

type CheckoutResponse = { checkout_url: string }
type PortalResponse = { portal_url: string }

export async function createCheckoutSession(planKey: string): Promise<string> {
  const payload = await apiFetch<CheckoutResponse>(API_ROUTES.subscriptionCheckout, {
    method: 'POST',
    credentials: 'same-origin',
    body: JSON.stringify({ plan_key: planKey }),
  })
  return payload.checkout_url
}

export async function createBillingPortalSession(): Promise<string> {
  const payload = await apiFetch<PortalResponse>(API_ROUTES.subscriptionPortal, {
    method: 'POST',
    credentials: 'same-origin',
  })
  return payload.portal_url
}
