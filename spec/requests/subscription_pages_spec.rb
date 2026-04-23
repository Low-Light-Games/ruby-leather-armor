require "rails_helper"

RSpec.describe "Subscription pages", type: :request do
  let(:user) { create(:user) }
  let(:admin_user) { create(:user, :admin) }

  before { sign_in_via_session(user) }

  it "renders the plans page" do
    get plans_path
    expect(response).to have_http_status(:ok)
  end

  it "renders the subscription success page" do
    create(:user_stripe_profile, user: user, stripe_customer_id: "cus_123")
    checkout_session = OpenStruct.new(
      mode: "subscription",
      customer: "cus_123",
      client_reference_id: user.id.to_s
    )
    allow(StripeGateway).to receive(:retrieve_checkout_session).and_return(checkout_session)

    get subscription_success_path(session_id: "cs_test_123")
    expect(response).to have_http_status(:ok)
  end

  it "redirects to plans when session_id is missing for non-admin users" do
    get subscription_success_path
    expect(response).to redirect_to(plans_path)
  end

  it "redirects to plans when checkout session is invalid for the user" do
    checkout_session = OpenStruct.new(
      mode: "subscription",
      customer: "cus_other",
      client_reference_id: "999999"
    )
    allow(StripeGateway).to receive(:retrieve_checkout_session).and_return(checkout_session)

    get subscription_success_path(session_id: "cs_test_invalid")

    expect(response).to redirect_to(plans_path)
  end

  it "ignores success preview params for non-admin users" do
    create(:user_stripe_profile, user: user, stripe_customer_id: "cus_123")
    checkout_session = OpenStruct.new(
      mode: "subscription",
      customer: "cus_123",
      client_reference_id: user.id.to_s
    )
    allow(StripeGateway).to receive(:retrieve_checkout_session).and_return(checkout_session)

    get subscription_success_path(preview: "confirmed", session_id: "cs_test_123")
    expect(response.body).not_to include('data-preview-mode="confirmed"')
  end

  it "allows success preview params for admin users" do
    sign_in_via_session(admin_user)
    get subscription_success_path(preview: "pending")
    expect(response.body).to include('data-preview-mode="pending"')
  end
end
