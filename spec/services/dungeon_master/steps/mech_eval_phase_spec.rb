# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::Phases::MechEvalPhase ownership guards", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "drops inventory attack rolls that violate domain ownership" do
    allow(pipeline.instance_variable_get(:@log)).to receive(:play_log!)

    results = [{
      "meta" => { "domain" => "inventory" },
      "parsed_response" => {
        "player_rolls" => [
          { "type" => "attack_roll", "dc" => 16, "description" => "Ray of Frost attack against the goblin" }
        ],
        "npc_actions" => [],
        "consequences" => [],
        "mechanical_summary" => "bad inventory output"
      }
    }]

    parsed = pipeline.send(:parse_mech_eval_results, results, ["inventory"])

    expect(parsed).to contain_exactly(include(domain: "inventory", player_rolls: []))
    expect(pipeline.instance_variable_get(:@log)).to have_received(:play_log!).with(
      "ownership_guard",
      /Dropped inventory roll/,
      parsed_response: hash_including(domain: "inventory", violation: "forbidden_type")
    )
  end

  it "drops traversal stealth rolls that violate domain ownership" do
    allow(pipeline.instance_variable_get(:@log)).to receive(:play_log!)

    results = [{
      "meta" => { "domain" => "traversal" },
      "parsed_response" => {
        "player_rolls" => [
          { "type" => "skill_check", "skill" => "Stealth", "dc" => 12, "description" => "Sneak past the goblins" }
        ],
        "npc_actions" => [],
        "consequences" => [],
        "mechanical_summary" => "bad traversal output"
      }
    }]

    parsed = pipeline.send(:parse_mech_eval_results, results, ["traversal"])

    expect(parsed).to contain_exactly(include(domain: "traversal", player_rolls: []))
    expect(pipeline.instance_variable_get(:@log)).to have_received(:play_log!).with(
      "ownership_guard",
      /Dropped traversal roll/,
      parsed_response: hash_including(domain: "traversal", violation: "forbidden_skill")
    )
  end
end
