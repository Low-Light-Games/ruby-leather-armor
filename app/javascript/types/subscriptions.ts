export interface SubscriptionPlan {
  key: string
  token_limit: number
  amount: number | null
  /** USD list price in cents for /plans display when checkout currency differs (e.g. BRL). */
  usd: number | null
  description: string | null
}

export interface SubscriptionPlansProps {
  plans: SubscriptionPlan[]
  currentPlanKey: string
}
