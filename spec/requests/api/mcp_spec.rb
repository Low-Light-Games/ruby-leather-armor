# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Mcp" do
  let(:token) { "super-secret-mcp-token-#{SecureRandom.hex(4)}" }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  around do |example|
    ClimateControl.modify(MCP_BEARER_TOKEN: token) { example.run }
  rescue NameError
    # ClimateControl isn't in the Gemfile — fall back to direct ENV mutation.
    prev = ENV["MCP_BEARER_TOKEN"]
    ENV["MCP_BEARER_TOKEN"] = token
    begin
      example.run
    ensure
      ENV["MCP_BEARER_TOKEN"] = prev
    end
  end

  describe "auth" do
    it "rejects requests with no Authorization header" do
      get "/api/mcp/stories"
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects requests with a wrong bearer token" do
      get "/api/mcp/stories", headers: { "Authorization" => "Bearer not-the-token" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts requests with the right bearer token" do
      get "/api/mcp/stories", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/mcp/users/find" do
    it "finds a user by email (case-insensitive)" do
      user = create(:user, email: "Find.Me@example.com")
      get "/api/mcp/users/find", params: { email: "find.me@example.com" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("id" => user.id, "email" => "Find.Me@example.com")
    end

    it "returns not_found for an unknown email" do
      get "/api/mcp/users/find", params: { email: "nobody@example.com" }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "rejects calls with no filters so it can't leak an arbitrary first user" do
      create(:user)
      get "/api/mcp/users/find", headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to include("error" => "invalid_arguments")
    end
  end

  describe "GET /api/mcp/stories" do
    let!(:visible_story) { create(:story, world_terrain: "plains", hidden_from_players: false) }
    let!(:hidden_story)  { create(:story, world_terrain: "plains", hidden_from_players: true) }

    it "hides stories with hidden_from_players=true by default" do
      get "/api/mcp/stories", headers: headers
      ids = JSON.parse(response.body).map { |s| s["id"] }
      expect(ids).to include(visible_story.id)
      expect(ids).not_to include(hidden_story.id)
    end

    it "includes hidden stories when include_hidden=1" do
      get "/api/mcp/stories", params: { include_hidden: "1" }, headers: headers
      ids = JSON.parse(response.body).map { |s| s["id"] }
      expect(ids).to include(visible_story.id, hidden_story.id)
    end
  end

  describe "GET /api/mcp/adventures/:adventure_id/messages" do
    it "returns messages for the adventure in chronological order" do
      adventure = create(:adventure, story: create(:story, world_terrain: "plains"))
      m1 = create(:adventure_message, adventure: adventure, content: "first",  created_at: 2.minutes.ago)
      m2 = create(:adventure_message, adventure: adventure, content: "second", created_at: 1.minute.ago)
      _other = create(:adventure_message, adventure: create(:adventure, story: create(:story, world_terrain: "plains")))

      get "/api/mcp/adventures/#{adventure.id}/messages", headers: headers
      body = JSON.parse(response.body)
      expect(body.map { |m| m["id"] }).to eq([m1.id, m2.id])
    end
  end

  describe "GET /api/mcp/play_logs and /pipelines" do
    let(:adventure) { create(:adventure, story: create(:story, world_terrain: "plains")) }
    let(:uuid_a) { SecureRandom.uuid }
    let(:uuid_b) { SecureRandom.uuid }

    before do
      PlayLog.create!(adventure: adventure, event_type: "queue_completed", status: "pipeline_event",
                      prompt_summary: "x", registry_entry_uuid: uuid_a, created_at: 3.minutes.ago)
      PlayLog.create!(adventure: adventure, event_type: "pipeline_error",  status: "api_error",
                      prompt_summary: "y", registry_entry_uuid: uuid_a, created_at: 2.minutes.ago)
      PlayLog.create!(adventure: adventure, event_type: "queue_completed", status: "pipeline_event",
                      prompt_summary: "z", registry_entry_uuid: uuid_b, created_at: 1.minute.ago)
    end

    it "filters play_logs by registry_entry_uuid" do
      get "/api/mcp/play_logs", params: { registry_entry_uuid: uuid_a }, headers: headers
      body = JSON.parse(response.body)
      expect(body.size).to eq(2)
      expect(body.map { |l| l["registry_entry_uuid"] }.uniq).to eq([uuid_a])
    end

    it "groups pipelines by uuid and flags had_error" do
      get "/api/mcp/play_logs/pipelines", headers: headers
      body = JSON.parse(response.body)
      by_uuid = body.index_by { |row| row["registry_entry_uuid"] }
      expect(by_uuid[uuid_a]).to include("log_count" => 2, "had_error" => true)
      expect(by_uuid[uuid_b]).to include("log_count" => 1, "had_error" => false)
    end
  end
end
