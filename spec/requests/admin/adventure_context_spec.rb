# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Adventures#update_context", type: :request do
  let(:admin) { create(:user, :admin, :password_auth) }
  let(:user)  { create(:user, :password_auth) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: admin, story: story, traversal_context: { location: "forest" }) }

  let(:json_headers) { { "Accept" => "application/json", "Content-Type" => "application/json" } }

  def patch_context(field:, value:, as_user: admin)
    sign_in_via_session(as_user)
    patch "/admin/adventures/#{adventure.id}",
      params: { context_field: field, context_value: value.to_json }.to_json,
      headers: json_headers
  end

  describe "happy path" do
    it "returns 200 and updates the DB" do
      patch_context(field: "traversal", value: { location: "cave", danger: "high" })
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["context_field"]).to eq("traversal")
      expect(body["context_value"]).to include("location" => "cave")
      expect(adventure.reload.traversal_context).to include("location" => "cave")
    end
  end

  describe "unknown field" do
    it "returns 422" do
      patch_context(field: "bogus", value: {})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/unknown context/i)
    end
  end

  describe "invalid JSON" do
    it "returns 422" do
      sign_in_via_session(admin)
      patch "/admin/adventures/#{adventure.id}",
        params: { context_field: "traversal", context_value: "not { valid json" }.to_json,
        headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "non-admin user" do
    it "is rejected" do
      patch_context(field: "traversal", value: {}, as_user: user)
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end
  end
end
