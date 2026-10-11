require "rails_helper"

RSpec.describe "Definition catalog caching", type: :request do
  before do
    sign_in(create(:user, :password_auth))
    FeatDefinition.create!(id: "power_attack", name: "Power Attack", category: "combat")
    FeatDefinition.create!(id: "spell_focus", name: "Spell Focus", category: "general")
  end

  it "serves the unfiltered catalog through the cache" do
    expect(CatalogJsonCache).to receive(:fetch).with(FeatDefinition).and_call_original

    get "/feat_definitions", headers: { "Accept" => "application/json" }

    expect(response.parsed_body.pluck("id")).to contain_exactly("power_attack", "spell_focus")
  end

  it "bypasses the cache for filtered requests" do
    expect(CatalogJsonCache).not_to receive(:fetch)

    get "/feat_definitions", params: { category: "combat" }, headers: { "Accept" => "application/json" }

    expect(response.parsed_body.pluck("id")).to eq(["power_attack"])
  end
end
