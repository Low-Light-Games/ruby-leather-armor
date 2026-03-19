require "rails_helper"

RSpec.describe "Public routes", type: :request do
  describe "GET /up" do
    it "returns 200" do
      get "/up"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /legal" do
    it "returns 200" do
      get "/legal"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /privacy" do
    it "returns 200" do
      get "/privacy"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /" do
    it "renders the frontpage shell" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Leather Armor — Tabletop RPG Character Sheets")
      expect(response.body).to include("AI-driven adventure")
      expect(response.body).to include('id="frontpage-root"')
    end
  end

  describe "unauthenticated JSON API" do
    it "GET /feat_definitions returns 401 without auth" do
      get "/feat_definitions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /spell_definitions returns 401 without auth" do
      get "/spell_definitions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /item_definitions returns 401 without auth" do
      get "/item_definitions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
