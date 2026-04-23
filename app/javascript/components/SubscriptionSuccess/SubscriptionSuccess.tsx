import { useEffect, useState } from 'react'
import Navbar from '../Navbar'
import './SubscriptionSuccess.scss'

const MAX_ATTEMPTS = 15
const POLL_INTERVAL_MS = 2000

type Status = 'syncing' | 'confirmed' | 'pending'

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

export const SubscriptionSuccess = () => {
  const [status, setStatus] = useState<Status>('syncing')

  useEffect(() => {
    let cancelled = false

    const poll = async () => {
      for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
        if (cancelled) return

        const response = await fetch('/current_user', { credentials: 'same-origin' })
        if (response.ok) {
          const payload = await response.json()
          const planKey = payload?.user?.plan_key
          if (planKey && planKey !== 'free') {
            setStatus('confirmed')
            return
          }
        }

        await wait(POLL_INTERVAL_MS)
      }

      if (!cancelled) {
        setStatus('pending')
      }
    }

    poll().catch(() => {
      if (!cancelled) setStatus('pending')
    })

    return () => {
      cancelled = true
    }
  }, [])

  return (
    <div className="app">
      <Navbar />
      <div className="subscription-success-page">
        {status === 'syncing' && (
          <>
            <h1>Finalizing your subscription...</h1>
            <p>We are waiting for Stripe confirmation. This usually takes a few seconds.</p>
          </>
        )}

        {status === 'confirmed' && (
          <>
            <h1>Subscription confirmed</h1>
            <p>Your plan is active. You can continue your adventure now.</p>
            <a href="/adventures/new" className="subscription-success-link">Start adventure</a>
          </>
        )}

        {status === 'pending' && (
          <>
            <h1>Payment received, still syncing</h1>
            <p>
              Your subscription is processing. Refresh this page in a moment, or continue playing while we finish
              webhook sync.
            </p>
            <a href="/adventures/new" className="subscription-success-link">Continue to adventures</a>
          </>
        )}
      </div>
    </div>
  )
}

export default SubscriptionSuccess
