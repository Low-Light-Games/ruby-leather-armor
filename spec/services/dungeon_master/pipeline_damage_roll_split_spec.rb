# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::PipelineEngine — attack and damage roll splitting", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 14, wisdom: 10, charisma: 10,
      race: "human", character_class: "wizard", level: 1)
  end
  let(:pipeline) { build_pipeline(adventure) }

  def paused_loop_for(action_text)
    AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: pipeline.instance_variable_get(:@log).registry_entry_uuid,
      sequence_index: 0,
      raw_action: action_text,
      player_intent: action_text,
      status: "paused"
    )
  end

  it "pauses for a damage roll after a successful opener attack roll before initiative" do
    paused_loop_for("I cast Ray of Frost on the goblin")
    allow(pipeline).to receive(:battlefield_roll_version_mismatch?).and_return(false)
    allow(DungeonMaster::Rolls::PlayerRolls).to receive(:tag_roll_resolution!)
    allow(DungeonMaster::ContextUpdatePause).to receive(:run)
    expect(pipeline).not_to receive(:run_mechanic)

    metadata = {
      "intent" => {
        "intention" => "I cast Ray of Frost on the goblin",
        "needs_mechanics" => true,
        "expand_scene" => false,
        "affected_contexts" => ["combat"],
        "macro_significant" => false,
        "domain_results" => {},
        "creature_data" => [{ "name" => "Goblin", "creature_sheet_id" => 123, "initiative" => 10 }]
      },
      "mechanical_summaries" => ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."],
      "roll_requests" => [
        { "type" => "attack_roll", "dc" => 16, "description" => "Ray of Frost against the goblin", "damage" => "1d3", "damage_type" => "cold", "target" => "goblin" }
      ],
      "pending_npc_actions" => [],
      "pending_consequences" => [],
      "remaining_actions" => []
    }

    result = pipeline.run_rolls(
      "Rolled 17 for: Ray of Frost against the goblin",
      metadata,
      submitted_rolls: [{ roll_value: 17, roll_description: "Ray of Frost against the goblin" }]
    )

    expect(result[:action]).to eq(:awaiting_rolls)
    expect(result[:merged][:player_rolls]).to contain_exactly(
      include(type: "damage_roll", damage: "1d3", damage_type: "cold")
    )
    expect(result[:merged][:roll_chain]).to include(phase: "damage")
  end

  it "resolves a miss without requesting a damage roll" do
    allow(pipeline).to receive(:resolve_npc_actions).and_return("")
    allow(pipeline).to receive(:run_mechanic).and_return(outcome: "Ray of Frost misses.", mutations: {})
    allow(pipeline).to receive(:run_time_keeper).and_return({ encounter: false })

    result = pipeline.send(
      :finish_resolution,
      { intention: "cast Ray of Frost", creature_data: [], affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ type: "attack_roll", dc: 16, description: "Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."]
      },
      "Rolled 3 for: Ray of Frost against the goblin",
      submitted_rolls: [{ roll_value: 3, roll_description: "Ray of Frost against the goblin" }]
    )

    expect(result[:status]).to eq(:resolved)
  end

  it "combines the prior attack roll and current damage roll before final resolution" do
    allow(pipeline).to receive(:resolve_npc_actions).and_return("")
    captured_rolls = nil
    allow(pipeline).to receive(:run_mechanic) do |_intent, _merged, roll_results:, npc_results:|
      captured_rolls = roll_results
      { outcome: "Ray of Frost hits for 2 cold damage.", mutations: {} }
    end
    allow(pipeline).to receive(:run_time_keeper).and_return({ encounter: false })

    pipeline.send(
      :finish_resolution,
      { intention: "cast Ray of Frost", creature_data: [], affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ type: "damage_roll", description: "Damage roll for Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."],
        roll_chain: {
          phase: "damage",
          prior_roll_results: "Rolled 17 for: Ray of Frost against the goblin",
          prior_submitted_rolls: [{ roll_value: 17, roll_description: "Ray of Frost against the goblin" }]
        }
      },
      "Rolled 2 for: Damage roll for Ray of Frost against the goblin",
      submitted_rolls: [{ roll_value: 2, roll_description: "Damage roll for Ray of Frost against the goblin" }]
    )

    expect(captured_rolls).to include("Rolled 17 for: Ray of Frost against the goblin")
    expect(captured_rolls).to include("Rolled 2 for: Damage roll for Ray of Frost against the goblin")
  end

  it "pauses for a damage roll before Combat GM resolves an active-combat hit" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [{ "name" => "Player" }, { "name" => "Goblin" }],
        "turn_order" => ["Player", "Goblin"],
        "current_turn" => "Player"
      }
    )
    expect(pipeline).not_to receive(:run_combat_gm)

    result = pipeline.send(
      :finish_resolution,
      { intention: "attack the goblin", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ type: "attack_roll", dc: 16, description: "Longsword attack against the goblin", damage: "1d8+3", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["The longsword attack requires an attack roll and deals 1d8+3 damage on a hit."]
      },
      "Rolled 18 for: Longsword attack against the goblin",
      submitted_rolls: [{ roll_value: 18, roll_description: "Longsword attack against the goblin" }]
    )

    expect(result[:status]).to eq(:awaiting_rolls)
    expect(result[:merged][:player_rolls]).to contain_exactly(include(type: "damage_roll", damage: "1d8+3"))
  end
end
