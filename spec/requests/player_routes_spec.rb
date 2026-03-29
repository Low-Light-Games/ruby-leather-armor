require "rails_helper"

RSpec.describe "Player routes", type: :request do
  let(:user) { create(:user) }

  # Stubs current_user so we don't need to replicate OAuth session setup.
  before { sign_in_via_session(user) }

  describe "GET /app/sheets" do
    it "returns 200 (React SPA)" do
      get "/app/sheets"
      expect(response).to have_http_status(:ok)
    end

    context "when not authenticated" do
      before { sign_in_via_session(nil) }

      it "returns 200 even without auth (SPA shell is public)" do
        get "/app/sheets"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /app/adventures/new" do
    it "returns 200 (React SPA entry point)" do
      get "/app/adventures/new"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "JSON API endpoints" do
    describe "GET /app/stories" do
      it "returns 200 with JSON" do
        get "/app/stories", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
      end
    end

    describe "GET /app/sheets (JSON)" do
      it "returns 200 with the user's sheets" do
        create(:sheet, user: user)
        get "/app/sheets", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end
    end

    describe "GET /app/adventures (JSON)" do
      it "returns 200 with the user's adventures" do
        get "/app/adventures", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /app/feat_definitions" do
      it "returns 200" do
        get "/app/feat_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /app/spell_definitions" do
      it "returns 200" do
        get "/app/spell_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /app/item_definitions" do
      it "returns 200" do
        get "/app/item_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /app/feature_flags" do
      it "returns 200" do
        get "/app/feature_flags", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "unauthenticated access to protected routes" do
    before { sign_in_via_session(nil) }

    it "GET /app/adventures returns 401" do
      get "/app/adventures", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /app/stories returns 401" do
      get "/app/stories", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
