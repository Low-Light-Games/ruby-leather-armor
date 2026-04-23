import { useMemo, useState } from 'react'
import { csrfToken } from '../../utils/api'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import './SubscriptionPlans.scss'

type Plan = {
  key: string
  token_limit: number
  amount: number | null
  description: string | null
}

type Props = {
  plans: Plan[]
  currentPlanKey: string
}

const formatPrice = (amount: number | null) => {
  if (amount == null) return 'Contact us'
  return `$${(amount / 100).toFixed(2)}/mo`
}

const formatLimit = (tokenLimit: number) => `${tokenLimit.toLocaleString()} tokens / month`

export const SubscriptionPlans = ({ plans, currentPlanKey }: Props) => {
  const { user } = useAuth()
  const [submittingPlan, setSubmittingPlan] = useState<string | null>(null)
  const [portalLoading, setPortalLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const sortedPlans = useMemo(
    () => [...plans].sort((a, b) => (a.amount ?? Number.MAX_SAFE_INTEGER) - (b.amount ?? Number.MAX_SAFE_INTEGER)),
    [plans],
  )

  const startCheckout = async (planKey: string) => {
    try {
      setError(null)
      setSubmittingPlan(planKey)
      const response = await fetch('/subscription/checkout', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        credentials: 'same-origin',
        body: JSON.stringify({ plan_key: planKey }),
      })

      const data = await response.json()
      if (!response.ok) {
        throw new Error(data.error || 'Unable to start checkout.')
      }

      window.location.href = data.checkout_url
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to start checkout.')
      setSubmittingPlan(null)
    }
  }

  const openPortal = async () => {
    try {
      setError(null)
      setPortalLoading(true)
      const response = await fetch('/subscription/portal', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken(),
        },
        credentials: 'same-origin',
      })

      const data = await response.json()
      if (!response.ok) {
        throw new Error(data.error || 'Unable to open billing portal.')
      }

      window.location.href = data.portal_url
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
                <p className="price">{formatPrice(plan.amount)}</p>
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
          </div>
        )}
      </div>
    </div>
  )
}

export default SubscriptionPlans
