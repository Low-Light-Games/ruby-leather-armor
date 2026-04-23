require "rails_helper"

RSpec.describe "Subscription pages", type: :request do
  let(:user) { create(:user) }

  before { sign_in_via_session(user) }

  it "renders the plans page" do
    get plans_path
    expect(response).to have_http_status(:ok)
  end

  it "renders the subscription success page" do
    get subscription_success_path
    expect(response).to have_http_status(:ok)
  end
end
