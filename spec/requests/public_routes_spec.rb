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
      expect(response.body).to include("AI Game Master for Solo d20 Adventures")
      expect(response.body).to include("AI Game Master for solo d20 adventures")
      expect(response.body).to include('id="frontpage-root"')
    end
  end

  describe "unauthenticated JSON API" do
    it "GET /app/feat_definitions returns 401 without auth" do
      get "/app/feat_definitions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /app/spell_definitions returns 401 without auth" do
      get "/app/spell_definitions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /app/item_definitions returns 401 without auth" do
      get "/app/item_definitions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
