# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Adventures context update (JSON)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }
  let(:adventure) do
    create(:adventure, traversal_context: { "current_location" => "Forest", "exits" => ["north"] })
  end

  let(:json_headers) { { "Accept" => "application/json", "Content-Type" => "application/json" } }

  def patch_context(field:, value:, as_user: admin)
    sign_in_via_session(as_user)
    patch "/admin/adventures/#{adventure.id}",
      params: { context_field: field, context_value: value.to_json }.to_json,
      headers: json_headers
  end

  describe "PATCH /admin/adventures/:id (JSON)" do
    context "when authenticated as admin" do
      it "updates the context and returns JSON" do
        new_value = { "current_location" => "Cave", "exits" => ["south"] }
        patch_context(field: "traversal", value: new_value)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["context_field"]).to eq("traversal")
        expect(body["context_value"]).to eq(new_value)
        expect(adventure.reload.traversal_context).to eq(new_value)
      end

      it "returns 422 for an unknown context field" do
        sign_in_via_session(admin)
        patch "/admin/adventures/#{adventure.id}",
          params: { context_field: "bogus", context_value: "{}" }.to_json,
          headers: json_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to match(/unknown context/i)
      end

      it "returns 422 for invalid JSON in context_value" do
        sign_in_via_session(admin)
        patch "/admin/adventures/#{adventure.id}",
          params: { context_field: "traversal", context_value: "not json" }.to_json,
          headers: json_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to match(/invalid json/i)
      end
    end

    context "when authenticated as a non-admin" do
      it "is rejected" do
        new_value = { "current_location" => "Tavern" }
        patch_context(field: "traversal", value: new_value, as_user: user)

        expect(response.status).to be_in([302, 403])
      end
    end

    context "when unauthenticated" do
      it "is rejected" do
        sign_in_via_session(nil)
        patch "/admin/adventures/#{adventure.id}",
          params: { context_field: "traversal", context_value: "{}" }.to_json,
          headers: json_headers

        expect(response.status).to be_in([302, 401, 403])
      end
    end
  end
end
