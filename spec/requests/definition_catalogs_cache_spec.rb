require "rails_helper"

RSpec.describe "Definition catalog caching", type: :request do
  let(:user) { create(:user, :password_auth) }

  before do
    sign_in(user)
    FeatDefinition.create!(id: "power_attack", name: "Power Attack", category: "combat")
    FeatDefinition.create!(id: "spell_focus", name: "Spell Focus", category: "general")
  end

  it "serves the unfiltered catalog through CatalogJsonCache" do
    expect(CatalogJsonCache).to receive(:fetch).with(FeatDefinition).and_call_original

    get "/feat_definitions", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck("id")).to contain_exactly("power_attack", "spell_focus")
  end

  it "bypasses the cache for filtered requests" do
    expect(CatalogJsonCache).not_to receive(:fetch)

    get "/feat_definitions", params: { category: "combat" }, headers: { "Accept" => "application/json" }

    expect(response.parsed_body.pluck("id")).to eq(["power_attack"])
  end

  it "serves every catalog as JSON in the camelCase shape the frontend expects" do
    %w[/feat_definitions /spell_definitions /item_definitions].each do |path|
      get path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    get "/feat_definitions", headers: { "Accept" => "application/json" }
    expect(response.parsed_body.first.keys).to include("choiceType")
  end
end
