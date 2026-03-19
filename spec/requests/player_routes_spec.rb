require "rails_helper"

RSpec.describe "Player routes", type: :request do
  let(:user) { create(:user) }

  # Stubs current_user so we don't need to replicate OAuth session setup.
  before { sign_in_via_session(user) }

  describe "GET /sheets" do
    it "returns 200 (React SPA)" do
      get "/sheets"
      expect(response).to have_http_status(:ok)
    end

    context "when not authenticated" do
      before { sign_in_via_session(nil) }

      it "returns 200 even without auth (SPA shell is public)" do
        get "/sheets"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /adventures/new" do
    it "returns 200 (React SPA entry point)" do
      get "/adventures/new"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "JSON API endpoints" do
    describe "GET /stories" do
      it "returns 200 with JSON" do
        get "/stories", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
      end
    end

    describe "GET /sheets (JSON)" do
      it "returns 200 with the user's sheets" do
        create(:sheet, user: user)
        get "/sheets", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end
    end

    describe "GET /adventures (JSON)" do
      it "returns 200 with the user's adventures" do
        get "/adventures", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /feat_definitions" do
      it "returns 200" do
        get "/feat_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /spell_definitions" do
      it "returns 200" do
        get "/spell_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /item_definitions" do
      it "returns 200" do
        get "/item_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /feature_flags" do
      it "returns 200" do
        get "/feature_flags", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "unauthenticated access to protected routes" do
    before { sign_in_via_session(nil) }

    it "GET /adventures returns 401" do
      get "/adventures", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /stories returns 401" do
      get "/stories", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
