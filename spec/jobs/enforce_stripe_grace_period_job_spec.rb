require "rails_helper"

RSpec.describe EnforceStripeGracePeriodJob, type: :job do
  it "downgrades only profiles with expired grace periods" do
    expired = create(
      :user_stripe_profile,
      plan_key: "novice",
      delinquent_since: 4.days.ago,
      grace_period_ends_at: 1.day.ago
    )
    active = create(
      :user_stripe_profile,
      plan_key: "scout",
      delinquent_since: 1.day.ago,
      grace_period_ends_at: 2.days.from_now
    )

    described_class.perform_now

    expect(expired.reload.plan_key).to eq("free")
    expect(expired.delinquent_since).to be_nil
    expect(expired.grace_period_ends_at).to be_nil
    expect(active.reload.plan_key).to eq("scout")
  end
end
