# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::FeatureFlags" do
  let(:admin_user) { create(:user, :password_auth, :admin) }
  let(:flag) { create(:feature_flag, key: "demo", description: "demo flag") }

  before { sign_in(admin_user) }

  describe "GET /admin/feature_flags" do
    it "renders the flag list with current mode and bucketing summary" do
      flag # touch
      bucketed = create(:feature_flag, :modulo, key: "rolling_out", modulo_divisor: 10, modulo_on_remainders: [0])
      get "/admin/feature_flags"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("demo")
      expect(response.body).to include("rolling_out")
      expect(response.body).to include("modulo 10")
    end
  end

  describe "PATCH /admin/feature_flags/:id (mode flips)" do
    it "switches off → on" do
      patch "/admin/feature_flags/#{flag.id}", params: { feature_flag: { mode: "on" } }
      expect(response).to redirect_to(admin_feature_flags_path)
      expect(flag.reload.mode).to eq("on")
    end

    it "switches on → bucketed/granular and parses pasted user IDs" do
      patch "/admin/feature_flags/#{flag.id}", params: {
        feature_flag: {
          mode: "bucketed",
          bucketing_strategy: "granular",
          granular_user_ids_raw: "  3, 17\n42 17 "
        }
      }
      expect(response).to redirect_to(admin_feature_flags_path)
      flag.reload
      expect(flag.mode).to eq("bucketed")
      expect(flag.bucketing_strategy).to eq("granular")
      expect(flag.granular_user_ids).to eq([3, 17, 42])
    end

    it "switches to bucketed/modulo with checkbox-array remainders" do
      patch "/admin/feature_flags/#{flag.id}", params: {
        feature_flag: {
          mode: "bucketed",
          bucketing_strategy: "modulo",
          modulo_divisor: "10",
          modulo_on_remainders: %w[0 1 2]
        }
      }
      flag.reload
      expect(flag.mode).to eq("bucketed")
      expect(flag.bucketing_strategy).to eq("modulo")
      expect(flag.modulo_divisor).to eq(10)
      expect(flag.modulo_on_remainders).to eq([0, 1, 2])
    end

    it "clears bucketing config when flipping back to off" do
      flag.update!(mode: "bucketed", bucketing_strategy: "granular", granular_user_ids: [1, 2, 3])
      patch "/admin/feature_flags/#{flag.id}", params: { feature_flag: { mode: "off" } }
      flag.reload
      expect(flag.mode).to eq("off")
      expect(flag.bucketing_strategy).to be_nil
      expect(flag.granular_user_ids).to eq([])
    end

    it "re-renders the edit form on validation failure" do
      patch "/admin/feature_flags/#{flag.id}", params: {
        feature_flag: {
          mode: "bucketed",
          bucketing_strategy: "modulo",
          modulo_divisor: "11",
          modulo_on_remainders: ["0"]
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Modulo divisor")
    end
  end

  describe "non-admin access" do
    let(:regular_user) { create(:user, :password_auth) }

    it "denies access to a regular user" do
      sign_out
      sign_in(regular_user)
      get "/admin/feature_flags"
      expect(response).not_to have_http_status(:ok)
    end
  end
end

RSpec.describe "FeatureFlags (public endpoint)" do
  let(:user) { create(:user, :password_auth) }

  before { sign_in(user) }

  it "returns only flags enabled for the current user" do
    create(:feature_flag, key: "always_on", mode: "on")
    create(:feature_flag, key: "never_on", mode: "off")
    create(:feature_flag, :granular, key: "for_me", granular_user_ids: [user.id])
    create(:feature_flag, :granular, key: "not_for_me", granular_user_ids: [user.id + 1000])

    get "/feature_flags"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["enabled"]).to contain_exactly("always_on", "for_me")
  end
end
