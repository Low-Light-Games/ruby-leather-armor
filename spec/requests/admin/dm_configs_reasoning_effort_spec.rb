require "rails_helper"

RSpec.describe "Admin DM config reasoning effort", type: :request do
  let(:admin_user) { create(:user, :admin, :password_auth) }
  let!(:dm_config) { DmConfig.instance }

  before { sign_in(admin_user) }

  describe "GET /admin/dm_config" do
    it "renders the global reasoning_effort selector and per-step effort selects" do
      allow_any_instance_of(Admin::DmConfigsController)
        .to receive(:fetch_available_model_ids).and_return([DmConfig::DEFAULTS["model"]])

      get admin_dm_config_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="reasoning_effort"')
      expect(response.body).to include('name="step_reasoning_efforts[narrate]"')
    end
  end

  describe "PATCH /admin/dm_config" do
    before do
      allow_any_instance_of(Admin::DmConfigsController)
        .to receive(:fetch_available_model_ids).and_return([DmConfig::DEFAULTS["model"]])
    end

    it "persists the global reasoning_effort when valid" do
      patch admin_dm_config_path, params: { reasoning_effort: "high" }

      expect(dm_config.reload.get("reasoning_effort")).to eq("high")
    end

    it "ignores an invalid global reasoning_effort" do
      original = dm_config.get("reasoning_effort")
      patch admin_dm_config_path, params: { reasoning_effort: "absurd" }

      expect(dm_config.reload.get("reasoning_effort")).to eq(original)
    end

    it "persists per-step reasoning_effort overrides only for valid values" do
      patch admin_dm_config_path, params: {
        step_reasoning_efforts: { "narrate" => "medium", "intake" => "bogus", "mechanic" => "" }
      }

      stored = dm_config.reload.get("step_reasoning_efforts")
      expect(stored).to eq("narrate" => "medium")
    end

    it "drops a previously stored per-step override when the user clears it" do
      dm_config.update!(settings: dm_config.settings.merge(
        "step_reasoning_efforts" => { "narrate" => "high" }
      ))

      patch admin_dm_config_path, params: {
        step_reasoning_efforts: { "narrate" => "" }
      }

      expect(dm_config.reload.get("step_reasoning_efforts")).to eq({})
    end
  end
end
