export interface SubscriptionPlan {
  key: string
  token_limit: number
  amount: number | null
  description: string | null
}

export interface SubscriptionPlansProps {
  plans: SubscriptionPlan[]
  currentPlanKey: string
}
