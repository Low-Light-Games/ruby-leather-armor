# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::Phases::BeaconPhase#converge_beacons", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "expands compact combatant manifests into the internal combatant list" do
    results = [
      {
        "meta" => { "domain" => "combat" },
        "parsed_response" => {
          "affected" => true,
          "needs_mechanics" => true,
          "macro_significant" => false,
          "expand_scene" => false,
          "transition" => "combat_started",
          "destination" => nil,
          "combatants" => [{ "goblin" => 2 }, { "hobgoblin" => 1 }],
          "reasoning" => "Two goblins close in."
        }
      }
    ]

    intent = pipeline.send(:converge_beacons, results, "I cast Ray of Frost at the goblins")

    expect(intent[:domain_results]["combat"][:combatants]).to eq(["goblin", "goblin", "hobgoblin"])
  end
end
