# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::Phases::MechEvalPhase ownership guards", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  let!(:ray_of_frost) do
    SpellDefinition.create!(
      id: "ray_of_frost",
      name: "Ray of Frost",
      school: "evocation",
      class_levels: { "fighter" => 0 },
      components: %w[V S],
      casting_time: "1 standard action",
      range: "close",
      duration: "instantaneous",
      saving_throw: "none",
      spell_resistance: false,
      effects: [{ "type" => "damage", "dice" => "1d3", "damageType" => "cold" }],
      summary: "Ranged touch attack deals 1d3 cold damage."
    )
  end

  before do
    sheet.adventure_sheet_spells.create!(spell_id: ray_of_frost.id, storage_type: "spellbook")
  end

  it "renders combat mech-eval prompts with attack_option_id and compact attack options" do
    prompts = pipeline.send(
      :build_mech_eval_prompts,
      ["combat"],
      "I cast Ray of Frost at the goblin.",
      { affected_contexts: ["combat"] }
    )

    prompt = prompts.first.fetch(:system_prompt_base)
    expect(prompt).to include("attack_option_id")
    expect(prompt).not_to include("\"defense_kind\":")
    expect(prompt).to include("PLAYER ATTACK OPTIONS")
    expect(prompt).to include("spell:ray_of_frost | Ray of Frost | 1d3 cold")
  end

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
