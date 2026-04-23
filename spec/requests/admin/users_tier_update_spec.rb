require "rails_helper"

RSpec.describe "Admin user plan updates", type: :request do
  let(:admin_user) { create(:user, :admin) }
  let(:normal_user) { create(:user) }
  let(:target_user) { create(:user) }

  describe "PATCH /admin/users/:id/update_plan" do
    it "updates the plan when performed by an admin" do
      sign_in_via_session(admin_user)

      patch update_plan_admin_user_path(target_user), params: { user: { plan_key: "scout" } }

      expect(response).to redirect_to(admin_users_path)
      expect(target_user.reload.plan_key).to eq("scout")
    end

    it "does not update the plan for invalid values" do
      sign_in_via_session(admin_user)

      patch update_plan_admin_user_path(target_user), params: { user: { plan_key: "enterprise" } }

      expect(response).to redirect_to(admin_users_path)
      expect(target_user.reload.plan_key).to eq("free")
    end

    it "rejects non-admin users" do
      sign_in_via_session(normal_user)

      patch update_plan_admin_user_path(target_user), params: { user: { plan_key: "scout" } }

      expect(response.status).to be_in([302, 403])
      expect(target_user.reload.plan_key).to eq("free")
    end
  end
end
