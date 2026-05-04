# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Adventures#update_context", type: :request do
  let!(:admin) { create(:user, :admin, :password_auth) }
  let!(:user)  { create(:user, :password_auth) }
  let!(:story) { create(:story) }
  let!(:adventure) { create(:adventure, user: admin, story: story, combat_context: { active: false }) }

  def patch_context(field:, value:, as_user: admin)
    sign_in(as_user)
    patch "/admin/adventures/#{adventure.id}",
      params: { context_field: field, context_value: value.to_json },
      headers: { "Accept" => "application/json" }
  end

  describe "happy path" do
    it "returns 200 and updates the DB" do
      patch_context(field: "combat", value: { active: true, round: 1 })
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["context_field"]).to eq("combat")
      expect(body["context_value"]).to include("active" => true)
      expect(adventure.reload.combat_context).to include("active" => true)
    end
  end

  describe "unknown field" do
    it "returns 422" do
      patch_context(field: "traversal", value: {})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/unknown context/i)
    end
  end

  describe "invalid JSON" do
    it "returns 422" do
      sign_in(admin)
      patch "/admin/adventures/#{adventure.id}",
        params: { context_field: "combat", context_value: "not { valid json" },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "non-admin user" do
    it "is rejected" do
      patch_context(field: "combat", value: {}, as_user: user)
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end
  end
end
