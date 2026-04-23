require "rails_helper"

RSpec.describe "Stripe webhooks", type: :request do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_stripe_profile, user: user, plan_key: "free", stripe_customer_id: "cus_123") }
  let(:price_id) { StripePlans.fetch("scout").stripe_price_id }
  let(:period_end_unix) { 2.days.from_now.to_i }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("STRIPE_WEBHOOK_SECRET").and_return("whsec_test")
  end

  it "updates subscription state from checkout.session.completed and is idempotent" do
    event = OpenStruct.new(
      id: "evt_123",
      type: "checkout.session.completed",
      data: OpenStruct.new(
        object: OpenStruct.new(
          customer: "cus_123",
          subscription: "sub_123",
          metadata: { "user_id" => user.id.to_s }
        )
      ),
      to_json: "{\"id\":\"evt_123\"}"
    )

    subscription = OpenStruct.new(
      id: "sub_123",
      status: "active",
      current_period_end: period_end_unix,
      items: OpenStruct.new(data: [OpenStruct.new(price: OpenStruct.new(id: price_id))])
    )

    allow(StripeGateway).to receive(:construct_event).and_return(event)
    allow(StripeGateway).to receive(:retrieve_subscription).and_return(subscription)

    post stripe_webhooks_path, headers: { "Stripe-Signature" => "sig_test" }
    post stripe_webhooks_path, headers: { "Stripe-Signature" => "sig_test" }

    expect(response).to have_http_status(:ok)
    expect(profile.reload.plan_key).to eq("scout")
    expect(profile.stripe_subscription_id).to eq("sub_123")
    expect(StripeWebhookEvent.where(stripe_event_id: "evt_123").count).to eq(1)
  end

  it "marks profile delinquent when invoice payment fails" do
    event = OpenStruct.new(
      id: "evt_payment_failed",
      type: "invoice.payment_failed",
      data: OpenStruct.new(
        object: OpenStruct.new(customer: "cus_123")
      ),
      to_json: "{\"id\":\"evt_payment_failed\"}"
    )

    allow(StripeGateway).to receive(:construct_event).and_return(event)

    post stripe_webhooks_path, headers: { "Stripe-Signature" => "sig_test" }

    expect(response).to have_http_status(:ok)
    expect(profile.reload.delinquent_since).to be_present
    expect(profile.grace_period_ends_at).to be_present
  end
end
