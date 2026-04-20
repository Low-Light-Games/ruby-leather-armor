# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::AdventureLoopResolution social scene routing", type: :service do
  include_context "with mocked ai"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "keeps pure social expansion on the world-only gate without capability check" do
    intent = {
      intention: "I haggle with the merchant over the relic.",
      affected_contexts: ["social"],
      expand_scene: true,
      macro_significant: false,
      domain_results: {
        "social" => { domain: "social", affected: true, expand_scene: true }
      }
    }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, []])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(false)
    allow(pipeline).to receive(:run_world_consistency_check).with(intent).and_return({ consistent: true })
    allow(pipeline).to receive(:resolve_social_scene).with(intent).and_return(status: :social_scene, intent: intent)
    expect(pipeline).not_to receive(:run_capability_check)
    expect(pipeline).not_to receive(:run_sanity_gate_fan_out)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:social_scene)
  end

  it "returns awaiting_rolls when mechanics require player rolls" do
    intent = { intention: "I pick the lock.", affected_contexts: ["exploration"], expand_scene: false }
    merged = { player_rolls: [{ type: "skill_check", skill: "Disable Device", dc: 15 }] }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, [{ domain: "exploration" }]])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(true)
    allow(pipeline).to receive(:run_capability_check).with(intent).and_return(allowed: true)
    allow(pipeline).to receive(:merge_mechanical_evaluations_and_prepare_rolls).with([{ domain: "exploration" }]).and_return(merged)
    expect(pipeline).not_to receive(:finish_resolution)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:awaiting_rolls)
    expect(result[:intent]).to eq(intent)
    expect(result[:merged]).to eq(merged)
  end

  it "returns resolved from mechanics path when no player rolls remain" do
    intent = { intention: "I carefully inspect the seal.", affected_contexts: ["exploration"], expand_scene: false }
    resolved = { status: :resolved, intent: intent, mutations: {}, time_result: { encounter: false } }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, [{ domain: "exploration" }]])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(true)
    allow(pipeline).to receive(:run_capability_check).with(intent).and_return(allowed: true)
    allow(pipeline).to receive(:merge_mechanical_evaluations_and_prepare_rolls).and_return(player_rolls: [])
    allow(pipeline).to receive(:finish_resolution).and_return(resolved)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:resolved)
  end

  it "returns rejected when world consistency fails on mechanics path" do
    intent = { intention: "I attack the nonexistent goblin.", affected_contexts: ["combat"], expand_scene: false }
    world = { consistent: false, reason: "No target in scene", dm_message: "No goblin is present." }
    rejected = { status: :rejected, reason: world[:reason], dm_message: world[:dm_message] }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, [{ domain: "combat" }]])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(false)
    allow(pipeline).to receive(:run_sanity_gate_fan_out).with(intent).and_return([world, { allowed: true }])
    allow(pipeline).to receive(:world_check_rejection).with(intent, world).and_return(rejected)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:rejected)
    expect(result[:reason]).to include("No target")
  end

  it "returns encounter when world-only path triggers harbinger encounter" do
    intent = { intention: "I wait and listen.", affected_contexts: [], expand_scene: false }
    time_result = { encounter: true, hours_elapsed: 1.0 }
    encounter = { status: :encounter, intent: intent, time_result: time_result }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, []])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(false)
    allow(pipeline).to receive(:run_world_consistency_check).with(intent).and_return(consistent: true)
    allow(pipeline).to receive(:run_time_keeper).with(intent, nil).and_return(time_result)
    allow(pipeline).to receive(:dispatch_encounter_warmaster).with(intent, time_result, mutations: nil).and_return(encounter)
    expect(pipeline).not_to receive(:run_momentum)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:encounter)
  end

  it "returns awaiting_initiative when finish_resolution hands off prepared combat" do
    intent = { intention: "I kick open the door.", affected_contexts: ["combat"], expand_scene: false }
    awaiting = { status: :awaiting_initiative, intent: intent, creature_data: [{ "name" => "Goblin" }] }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, [{ domain: "combat" }]])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(true)
    allow(pipeline).to receive(:run_capability_check).with(intent).and_return(allowed: true)
    allow(pipeline).to receive(:merge_mechanical_evaluations_and_prepare_rolls).and_return(player_rolls: [])
    allow(pipeline).to receive(:finish_resolution).and_return(awaiting)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:awaiting_initiative)
  end
end
