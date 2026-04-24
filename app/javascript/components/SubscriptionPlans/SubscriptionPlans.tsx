import { useMemo, useState } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { createBillingPortalSession, createCheckoutSession } from '../../services/subscriptionService'
import type { SubscriptionPlansProps } from '../../types/subscriptions'
import Navbar from '../Navbar'
import Login from '../Login'
import './SubscriptionPlans.scss'

const formatUsdPerMo = (usdCents: number | null | undefined, fallbackCents: number | null) => {
  const cents = usdCents ?? fallbackCents
  if (cents == null) return 'Contact us'
  return `$${(cents / 100).toFixed(2)} USD/mo`
}

const formatLimit = (tokenLimit: number) => `${tokenLimit.toLocaleString()} tokens / month`

export const SubscriptionPlans = ({ plans, currentPlanKey }: SubscriptionPlansProps) => {
  const { user } = useAuth()
  const [submittingPlan, setSubmittingPlan] = useState<string | null>(null)
  const [portalLoading, setPortalLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const sortedPlans = useMemo(
    () =>
      [...plans].sort(
        (a, b) =>
          (a.usd ?? a.amount ?? Number.MAX_SAFE_INTEGER) - (b.usd ?? b.amount ?? Number.MAX_SAFE_INTEGER),
      ),
    [plans],
  )

  if (!user) return <Login />

  const startCheckout = async (planKey: string) => {
    try {
      setError(null)
      setSubmittingPlan(planKey)
      const checkoutUrl = await createCheckoutSession(planKey)
      window.location.href = checkoutUrl
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to start checkout.')
      setSubmittingPlan(null)
    }
  }

  const openPortal = async () => {
    try {
      setError(null)
      setPortalLoading(true)
      const portalUrl = await createBillingPortalSession()
      window.location.href = portalUrl
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to open billing portal.')
      setPortalLoading(false)
    }
  }

  return (
    <div className="app">
      <Navbar />
      <div className="subscription-plans-page">
        <header className="subscription-plans-header">
          <h1>Choose your plan</h1>
          <p>Pick the token budget that matches your campaign pace.</p>
        </header>

        {error && <p className="subscription-plans-error">{error}</p>}

        <div className="subscription-plans-grid">
          {sortedPlans.map((plan) => {
            const current = currentPlanKey === plan.key
            const loading = submittingPlan === plan.key

            return (
              <article key={plan.key} className={`subscription-plan-card ${current ? 'current' : ''}`}>
                <h2>{plan.key}</h2>
                <p className="price">{formatUsdPerMo(plan.usd, plan.amount)}</p>
                <p className="limit">{formatLimit(plan.token_limit)}</p>
                {plan.description && <p className="description">{plan.description}</p>}

                <button
                  type="button"
                  className="subscribe-button"
                  disabled={loading || current}
                  onClick={() => startCheckout(plan.key)}
                >
                  {current ? 'Current plan' : loading ? 'Redirecting...' : 'Subscribe'}
                </button>
              </article>
            )
          })}
        </div>

        {user && (
          <div className="subscription-manage">
            <button type="button" className="portal-button" onClick={openPortal} disabled={portalLoading}>
              {portalLoading ? 'Opening portal...' : 'Manage billing'}
            </button>
            {user.admin && (
              <div className="subscription-preview-links">
                <a href="/subscription/success?preview=confirmed">Preview success</a>
                <a href="/subscription/success?preview=pending">Preview pending</a>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

export default SubscriptionPlans
