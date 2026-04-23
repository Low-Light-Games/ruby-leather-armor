require "rails_helper"

RSpec.describe "Subscriptions", type: :request do
  let(:user) { create(:user) }

  before { sign_in_via_session(user) }

  describe "POST /subscription/checkout" do
    it "creates a checkout session for a paid plan" do
      allow(StripeGateway).to receive(:create_customer).and_return(OpenStruct.new(id: "cus_123"))
      allow(StripeGateway).to receive(:create_checkout_session).and_return(OpenStruct.new(url: "https://stripe.test/checkout"))

      post subscription_checkout_path, params: { plan_key: "novice" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("checkout_url")).to eq("https://stripe.test/checkout")
      expect(user.reload.stripe_profile.stripe_customer_id).to eq("cus_123")
    end

    it "rejects free plan checkout requests" do
      post subscription_checkout_path, params: { plan_key: "free" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /subscription/portal" do
    it "returns an error when the user has no linked Stripe customer" do
      post subscription_portal_path

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates a billing portal session when customer exists" do
      create(:user_stripe_profile, user: user, stripe_customer_id: "cus_123")
      allow(StripeGateway).to receive(:create_billing_portal_session).and_return(OpenStruct.new(url: "https://stripe.test/portal"))

      post subscription_portal_path

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("portal_url")).to eq("https://stripe.test/portal")
    end
  end
end
