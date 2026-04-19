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
          "combat_now" => true,
          "combatants" => [{ "goblin" => 2 }, { "hobgoblin" => 1 }],
          "reasoning" => "Two goblins close in."
        }
      }
    ]

    intent = pipeline.send(:converge_beacons, results, "I cast Ray of Frost at the goblins")

    expect(intent[:domain_results]["combat"][:combatants]).to eq(["goblin", "goblin", "hobgoblin"])
    expect(intent[:domain_results]["combat"][:affected]).to be(true)
    expect(intent[:domain_results]["combat"][:transition]).to eq("combat_started")
  end

  it "logs single-creature combat manifests without mutating the roster" do
    allow(pipeline.instance_variable_get(:@log)).to receive(:play_log!)
    results = [
      {
        "meta" => { "domain" => "combat" },
        "parsed_response" => {
          "combat_now" => true,
          "combatants" => [{ "orc" => 1 }],
          "reasoning" => "Player initiated combat."
        }
      }
    ]

    intent = pipeline.send(:converge_beacons, results, "I charge at the orcs")

    expect(intent[:domain_results]["combat"][:combatants]).to eq(["orc"])
    expect(pipeline.instance_variable_get(:@log)).to have_received(:play_log!).with(
      "combat_beacon_single_manifest",
      /single-creature manifest/,
      parsed_response: hash_including(combatants: [{ orc: 1 }], count: nil)
    )
  end

  it "defines grouped-enemy count contract in combat beacon prompt" do
    rendered = DungeonMaster::PromptRenderer.render("combat_beacon",
      domain_context: nil,
      recent_messages: [],
      prior_outcomes: [])

    expect(rendered).to include("Do not collapse grouped enemies to a single creature.")
    expect(rendered).to include("emit explicit counted entries")
  end
end
