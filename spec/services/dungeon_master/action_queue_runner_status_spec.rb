# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::PipelineEngine::ActionQueueRunner status dispatch", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }
  let(:runner) { DungeonMaster::PipelineEngine::ActionQueueRunner.new(pipeline) }
  let(:loop_row) { instance_double(AdventureLoop, batch_update!: true) }

  before do
    allow(pipeline).to receive(:create_adventure_loop).and_return(loop_row)
    allow(pipeline).to receive(:run_inter_action_context_update)
    allow(pipeline).to receive(:run_accumulated_narrative_phase).and_return(action: :narrated, narrative: "stub")
    allow(pipeline).to receive(:run_context_updates_at_encounter_pause)
  end

  it "returns early on rejected status for fresh queues" do
    allow(pipeline).to receive(:resolve).with("first action").and_return(status: :rejected, reason: "invalid target")

    result = runner.run(
      action_strings: ["first action", "second action"],
      base_sequence_index: 0,
      total_for_logging: 2,
      abort_on_rejected: true
    )

    expect(result).to include(action: :rejected, reason: "invalid target")
    expect(pipeline).to have_received(:resolve).once
  end

  it "skips rejected action and continues when resuming queue" do
    allow(pipeline).to receive(:resolve).with("first action").and_return(status: :rejected, reason: "blocked")
    allow(pipeline).to receive(:resolve).with("second action").and_return(
      status: :resolved,
      intent: { intention: "second action" },
      mutations: {}
    )

    result = runner.run(
      action_strings: ["first action", "second action"],
      base_sequence_index: 0,
      total_for_logging: 2,
      abort_on_rejected: false
    )

    expect(result[:action]).to eq(:narrated)
    expect(pipeline).to have_received(:resolve).twice
  end

  it "returns early with remaining actions on awaiting_rolls" do
    allow(pipeline).to receive(:resolve).with("first action").and_return(
      status: :awaiting_rolls,
      intent: { intention: "first action" },
      merged: { player_rolls: [{ type: "skill_check", skill: "Stealth", dc: 12 }] }
    )

    result = runner.run(
      action_strings: ["first action", "second action"],
      base_sequence_index: 0,
      total_for_logging: 2,
      abort_on_rejected: true
    )

    expect(result[:action]).to eq(:awaiting_rolls)
    expect(result[:remaining_actions]).to eq([{
      "text" => "second action",
      "depends_on_index" => nil,
      "prerequisite" => nil,
      "abort_on_failed_prerequisite" => false
    }])
    expect(pipeline).to have_received(:resolve).once
  end

  it "breaks queue on encounter and narrates accumulated outcomes" do
    allow(pipeline).to receive(:resolve).with("first action").and_return(
      status: :encounter,
      intent: { intention: "first action" }
    )

    result = runner.run(
      action_strings: ["first action", "second action"],
      base_sequence_index: 0,
      total_for_logging: 2,
      abort_on_rejected: true
    )

    expect(result[:action]).to eq(:narrated)
    expect(pipeline).to have_received(:resolve).once
    expect(pipeline).to have_received(:run_accumulated_narrative_phase).once
  end
end
