require "rails_helper"

RSpec.describe "Subscription pages", type: :request do
  let(:user) { create(:user, :password_auth) }
  let(:admin_user) { create(:user, :admin, :password_auth) }

  before { sign_in(user) }

  it "renders the plans page" do
    get plans_path
    expect(response).to have_http_status(:ok)
  end

  it "renders the plans page when not logged in" do
    sign_out
    get plans_path
    expect(response).to have_http_status(:ok)
  end

  it "redirects to plans when session_id is missing for non-admin users" do
    get subscription_success_path
    expect(response).to redirect_to(plans_path)
  end

  it "allows success preview params for admin users" do
    sign_in(admin_user)
    get subscription_success_path(preview: "pending")
    expect(response.body).to include('data-preview-mode="pending"')
  end
end
