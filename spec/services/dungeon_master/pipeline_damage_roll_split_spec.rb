# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::PipelineEngine — attack and damage roll splitting", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:ai_responses) { AI_STEP_RESPONSES.merge("combat_gm" => combat_gm_response) }

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
  let!(:goblin) do
    CreatureSheet.create!(
      adventure: adventure,
      name: "Goblin", creature_type: "monster", origin: "template",
      hp: 8, max_hp: 8, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8
    )
  end
  let(:combat_gm_response) do
    {
      outcome: "Contradictory model prose.",
      reasoning: "stub",
      mutations: {}
    }.to_json
  end

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
        { "request_id" => "atk-1", "type" => "attack_roll", "dc" => 16, "description" => "Ray of Frost against the goblin", "damage" => "1d3", "damage_type" => "cold", "target" => "goblin" }
      ],
      "pending_npc_actions" => [],
      "pending_consequences" => [],
      "remaining_actions" => []
    }

    result = pipeline.run_rolls(
      "Rolled 17 for: Ray of Frost against the goblin",
      metadata,
      submitted_rolls: [{ request_id: "atk-1", roll_value: 17, roll_description: "Ray of Frost against the goblin" }]
    )

    expect(result[:action]).to eq(:awaiting_rolls)
    expect(result[:merged][:player_rolls]).to contain_exactly(
      include(type: "damage_roll", damage: "1d3", damage_type: "cold", source_request_id: "atk-1", request_id: "atk-1:damage")
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
        player_rolls: [{ request_id: "atk-1", type: "attack_roll", dc: 16, description: "Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."]
      },
      "Rolled 3 for: Ray of Frost against the goblin",
      submitted_rolls: [{ request_id: "atk-1", roll_value: 3, roll_description: "Ray of Frost against the goblin" }]
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
        player_rolls: [{ request_id: "atk-1:damage", source_request_id: "atk-1", type: "damage_roll", description: "Damage roll for Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."],
        roll_chain: {
          phase: "damage",
          prior_roll_results: "Rolled 17 for: Ray of Frost against the goblin",
          prior_submitted_rolls: [{ request_id: "atk-1", roll_value: 17, roll_description: "Ray of Frost against the goblin" }]
        }
      },
      "Rolled 2 for: Damage roll for Ray of Frost against the goblin",
      submitted_rolls: [{ request_id: "atk-1:damage", roll_value: 2, roll_description: "Damage roll for Ray of Frost against the goblin" }]
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
        player_rolls: [{ request_id: "atk-2", type: "attack_roll", dc: 16, description: "Longsword attack against the goblin", damage: "1d8+3", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["The longsword attack requires an attack roll and deals 1d8+3 damage on a hit."]
      },
      "Rolled 18 for: Longsword attack against the goblin",
      submitted_rolls: [{ request_id: "atk-2", roll_value: 18, roll_description: "Longsword attack against the goblin" }]
    )

    expect(result[:status]).to eq(:awaiting_rolls)
    expect(result[:merged][:player_rolls]).to contain_exactly(include(type: "damage_roll", damage: "1d8+3"))
  end

  it "retries active-combat mech-eval once when a hit is missing damage metadata" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [{ "name" => "Player" }, { "name" => "Goblin" }],
        "turn_order" => ["Player", "Goblin"],
        "current_turn" => "Player"
      }
    )
    expect(pipeline).not_to receive(:run_combat_gm)
    allow(pipeline).to receive(:retry_attack_damage_metadata).and_return([
      { request_id: "atk-3", type: "attack_roll", dc: 16, description: "Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "goblin" }
    ])

    result = pipeline.send(
      :finish_resolution,
      { intention: "cast Ray of Frost on the goblin", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ request_id: "atk-3", type: "attack_roll", dc: 16, description: "Ray of Frost against the goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll."]
      },
      "Rolled 18 for: Ray of Frost against the goblin",
      submitted_rolls: [{ request_id: "atk-3", roll_value: 18, roll_description: "Ray of Frost against the goblin" }]
    )

    expect(result[:status]).to eq(:awaiting_rolls)
    expect(result[:merged][:player_rolls]).to contain_exactly(include(type: "damage_roll", damage: "1d3"))
  end

  it "raises when an active-combat hit is still missing damage metadata after retry" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [{ "name" => "Player" }, { "name" => "Goblin" }],
        "turn_order" => ["Player", "Goblin"],
        "current_turn" => "Player"
      }
    )
    allow(pipeline).to receive(:retry_attack_damage_metadata).and_return([])

    expect {
      pipeline.send(
        :finish_resolution,
        { intention: "cast Ray of Frost on the goblin", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
        {
          player_rolls: [{ request_id: "atk-4", type: "attack_roll", dc: 16, description: "Ray of Frost against the goblin" }],
          npc_actions: [],
          consequences: [],
          mechanical_summaries: ["Ray of Frost requires an attack roll."]
        },
        "Rolled 18 for: Ray of Frost against the goblin",
        submitted_rolls: [{ request_id: "atk-4", roll_value: 18, roll_description: "Ray of Frost against the goblin" }]
      )
    }.to raise_error(DungeonMaster::AiError, /missing damage metadata/i)
  end

  it "falls back to legacy description matching when a paused pre-request-id attack roll resumes" do
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
      { intention: "cast Ray of Frost on the goblin", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ type: "attack_roll", dc: 16, description: "Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."]
      },
      "Rolled 18 for: Ray of Frost against the goblin",
      submitted_rolls: [{ roll_value: 18, roll_description: "Ray of Frost against the goblin" }]
    )

    expect(result[:status]).to eq(:awaiting_rolls)
    expect(result[:merged][:player_rolls]).to contain_exactly(
      include(type: "damage_roll", damage: "1d3", damage_type: "cold")
    )
  end

  it "resolves damage then surfaces goblin retaliation on the same active-combat pipeline" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "round" => 1,
        "participants" => [
          { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 20, "conditions" => [] },
          { "name" => "Goblin", "type" => "npc", "hp" => 8, "max_hp" => 8, "initiative" => 10, "conditions" => [], "creature_sheet_id" => goblin.id }
        ],
        "turn_order" => ["Player", "Goblin"],
        "current_turn" => "Player"
      }
    )

    allow(pipeline).to receive(:resolve_npc_actions).and_return("")
    allow(pipeline).to receive(:run_combat_gm).and_return(
      outcome: "Ray of Frost hits for 2 cold damage.",
      mutations: { npcs: [{ creature_sheet_id: goblin.id, name: "Goblin", hp_change: -2 }] }
    )
    allow(pipeline).to receive(:run_time_keeper).and_return({ encounter: false })
    allow(pipeline).to receive(:request_npc_actions).and_return([["npc_action__0"], {}])
    allow(pipeline).to receive(:evaluator_fan_out_result!).and_return({
      "parsed_response" => {
        "action" => "attack",
        "target" => "Player",
        "attack_modifier" => 1,
        "damage_dice" => "1d6+1",
        "battlefield_patches" => []
      }
    })
    allow(DungeonMaster::WorldTurn::NpcActionResolver).to receive(:resolve).and_return({
      lines: ["Goblin attacks Player: hit for 2."],
      player_hp_delta: -2,
      npc_muts: [],
      battlefield_patches: []
    })

    result = pipeline.send(
      :finish_resolution,
      { intention: "cast Ray of Frost on the goblin", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ request_id: "atk-5:damage", source_request_id: "atk-5", type: "damage_roll", description: "Damage roll for Ray of Frost against the goblin", damage: "1d3", damage_type: "cold", target: "Goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Ray of Frost requires an attack roll and deals 1d3 cold damage on a hit."],
        roll_chain: {
          phase: "damage",
          prior_roll_results: "Rolled 18 for: Ray of Frost against the goblin",
          prior_submitted_rolls: [{ request_id: "atk-5", roll_value: 18, roll_description: "Ray of Frost against the goblin" }]
        }
      },
      "Rolled 2 for: Damage roll for Ray of Frost against the goblin",
      submitted_rolls: [{ request_id: "atk-5:damage", roll_value: 2, roll_description: "Damage roll for Ray of Frost against the goblin" }]
    )

    expect(result[:status]).to eq(:resolved)
    expect(result[:world_turn_lines]).to eq(["Goblin attacks Player: hit for 2."])
    advancement = result.dig(:mutations, :combat_state_advancement) || result.dig(:mutations, "combat_state_advancement")
    expect(advancement).to be_present
  end

  it "overrides contradictory combat GM prose with a deterministic miss summary" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [{ "name" => "Player" }, { "name" => "Goblin" }],
        "turn_order" => ["Player", "Goblin"],
        "current_turn" => "Player"
      }
    )
    allow(pipeline).to receive(:resolve_npc_actions).and_return("")
    allow(pipeline).to receive(:run_time_keeper).and_return({ encounter: false })
    allow(pipeline).to receive(:run_context_updates).and_return(nil)
    allow(pipeline).to receive(:maybe_run_world_turn).and_wrap_original do |_original, **kwargs|
      kwargs
    end

    contradictory = {
      outcome: "Meein M'ecks successfully hits the goblin with an 8 against AC 12.",
      reasoning: "stub",
      mutations: {
        player: { hp_change: 0, conditions_add: [], conditions_remove: [], buffs_add: [], buffs_remove: [] },
        npcs: [{ name: "Goblin", creature_sheet_id: goblin.id, hp_change: 0, conditions_add: [], conditions_remove: [] }],
        inventory: {},
        battlefield_patches: [],
        action_economy_delta: { spend_standard: true, spend_move: false, spend_swift: false, spend_full_round: false },
        items_consumed: [],
        spells_used: ["Ray of Frost"]
      }
    }.to_json
    ai_responses["combat_gm"] = contradictory

    result = pipeline.send(
      :finish_resolution,
      { intention: "I cast Ray of Frost at it.", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
      {
        player_rolls: [{ request_id: "atk-9", type: "attack_roll", dc: 12, defense_kind: "touch_ac", description: "Ray of Frost attack", damage: "1d3", damage_type: "cold", target: "Goblin" }],
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Player casts Ray of Frost targeting the Goblin, requiring a ranged touch attack roll and dealing cold damage on a hit."]
      },
      "Rolled 8 for: Ray of Frost attack",
      submitted_rolls: [{ request_id: "atk-9", roll_value: 8, roll_description: "Ray of Frost attack" }]
    )

    expect(result[:action_outcome]).to eq("Ray of Frost attack vs Goblin: miss (8 vs Touch AC 12).")
  end
end
