import { useEffect, useState } from 'react'
import { fetchCurrentUser } from '../../services/authService'
import Navbar from '../Navbar'
import './SubscriptionSuccess.scss'
import { MAX_SUBSCRIPTION_SYNC_ATTEMPTS, SUBSCRIPTION_SYNC_INTERVAL_MS } from './constants'
import type { SubscriptionSuccessStatus } from './types'

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

export const SubscriptionSuccess = () => {
  const [status, setStatus] = useState<SubscriptionSuccessStatus>('syncing')

  useEffect(() => {
    let cancelled = false

    const poll = async () => {
      for (let attempt = 0; attempt < MAX_SUBSCRIPTION_SYNC_ATTEMPTS; attempt += 1) {
        if (cancelled) return

        const currentUser = await fetchCurrentUser()
        if (currentUser?.plan_key && currentUser.plan_key !== 'free') {
          setStatus('confirmed')
          return
        }

        await wait(SUBSCRIPTION_SYNC_INTERVAL_MS)
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
