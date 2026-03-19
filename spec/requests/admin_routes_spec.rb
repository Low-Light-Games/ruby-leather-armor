require "rails_helper"

# Admin controllers use require_admin which redirects to root for HTML
# or renders JSON 403 for JSON requests when the user is not an admin.
RSpec.describe "Admin routes", type: :request do
  let(:admin_user)  { create(:user, :admin) }
  let(:normal_user) { create(:user) }

  shared_examples "requires admin" do |http_method, path|
    context "when unauthenticated" do
      it "returns 401 or redirects" do
        sign_in_via_session(nil)
        public_send(http_method, path)
        expect(response.status).to be_in([401, 302])
      end
    end

    context "when authenticated as a non-admin" do
      it "returns 302 or 403" do
        sign_in_via_session(normal_user)
        public_send(http_method, path)
        expect(response.status).to be_in([302, 403])
      end
    end

    context "when authenticated as admin" do
      it "returns 200" do
        sign_in_via_session(admin_user)
        public_send(http_method, path)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  include_examples "requires admin", :get, "/admin/stories"
  include_examples "requires admin", :get, "/admin/adventures"
  include_examples "requires admin", :get, "/admin/feature_flags"
  include_examples "requires admin", :get, "/admin/bestiary_entries"
  include_examples "requires admin", :get, "/admin/play_logs"
  include_examples "requires admin", :get, "/admin/billing"
end
