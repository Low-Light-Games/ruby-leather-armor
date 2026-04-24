FactoryBot.define do
  factory :user_stripe_profile, class: "UserStripeProfile" do
    association :user
    plan_key { "free" }
    stripe_customer_id { nil }
    stripe_subscription_id { nil }
    stripe_subscription_status { nil }
    stripe_price_id { nil }
    stripe_current_period_end { nil }
    delinquent_since { nil }
    grace_period_ends_at { nil }
  end
end
