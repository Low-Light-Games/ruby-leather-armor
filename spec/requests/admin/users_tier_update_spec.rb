require "rails_helper"

RSpec.describe "Admin user plan updates", type: :request do
  let(:admin_user) { create(:user, :admin) }
  let(:normal_user) { create(:user) }
  let(:target_user) { create(:user, tier: "free") }

  describe "PATCH /admin/users/:id/update_tier" do
    it "updates the tier when performed by an admin" do
      sign_in_via_session(admin_user)

      patch update_tier_admin_user_path(target_user), params: { user: { tier: "paid" } }

      expect(response).to redirect_to(admin_users_path)
      expect(target_user.reload.tier).to eq("paid")
    end

    it "does not update the tier for invalid values" do
      sign_in_via_session(admin_user)

      patch update_tier_admin_user_path(target_user), params: { user: { tier: "enterprise" } }

      expect(response).to redirect_to(admin_users_path)
      expect(target_user.reload.tier).to eq("free")
    end

    it "rejects non-admin users" do
      sign_in_via_session(normal_user)

      patch update_tier_admin_user_path(target_user), params: { user: { tier: "paid" } }

      expect(response.status).to be_in([302, 403])
      expect(target_user.reload.tier).to eq("free")
    end
  end
end
