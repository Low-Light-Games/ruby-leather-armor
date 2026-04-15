# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::PipelineEngine::ActionQueueRunner prerequisite gating", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }
  let(:runner) { DungeonMaster::PipelineEngine::ActionQueueRunner.new(pipeline) }

  let(:conditional_entry) do
    {
      "text" => "cast Ray of Frost on one of the goblins",
      "depends_on_index" => 0,
      "prerequisite" => "stealth_approach_succeeded",
      "abort_on_failed_prerequisite" => true
    }
  end

  let(:failed_stealth_result) do
    {
      status: :resolved,
      intent: { intention: "move stealthily up to the goblins" },
      mutations: {},
      queue_resolution_context: {
        player_rolls: [
          { type: "skill_check", skill: "Stealth", dc: 10, description: "Stealth check to move silently closer" },
          { type: "skill_check", skill: "Stealth", dc: 15, description: "Stealth check to approach quietly" }
        ],
        roll_results: "Rolled 5 for: Stealth check to move silently closer\nRolled 10 for: Stealth check to approach quietly"
      }
    }
  end

  let(:successful_stealth_result) do
    failed_stealth_result.deep_dup.tap do |result|
      result[:queue_resolution_context][:roll_results] = "Rolled 21 for: Stealth check to move silently closer\nRolled 20 for: Stealth check to approach quietly"
    end
  end

  it "blocks a conditional follow-up when the stealth approach failed" do
    allow(pipeline).to receive(:run_accumulated_narrative_phase).and_return({ action: :narrated, narrative: "stub" })
    expect(pipeline).not_to receive(:resolve)

    result = runner.run(
      action_strings: [conditional_entry],
      base_sequence_index: 1,
      total_for_logging: 2,
      abort_on_rejected: false,
      initial_accumulated: [failed_stealth_result],
      per_action_narration: false
    )

    expect(result[:action]).to eq(:narrated)
  end

  it "continues a conditional follow-up when the stealth approach succeeded" do
    loop_row = AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: pipeline.instance_variable_get(:@log).registry_entry_uuid,
      sequence_index: 1,
      raw_action: conditional_entry["text"],
      player_intent: conditional_entry["text"],
      status: "pending"
    )
    allow(pipeline).to receive(:create_adventure_loop).and_return(loop_row)
    allow(pipeline).to receive(:resolve).with("cast Ray of Frost on one of the goblins").and_return(
      status: :resolved,
      intent: { intention: "cast Ray of Frost on one of the goblins" },
      mutations: {}
    )
    allow(pipeline).to receive(:run_accumulated_narrative_phase).and_return({ action: :narrated, narrative: "stub" })

    result = runner.run(
      action_strings: [conditional_entry],
      base_sequence_index: 1,
      total_for_logging: 2,
      abort_on_rejected: false,
      initial_accumulated: [successful_stealth_result],
      per_action_narration: false
    )

    expect(result[:action]).to eq(:narrated)
  end

  it "normalizes sequencer action hashes into structured queue entries" do
    allow(pipeline.instance_variable_get(:@config)).to receive(:get).and_call_original
    allow(pipeline.instance_variable_get(:@config)).to receive(:get).with("action_queue").and_return("progressive")
    allow(pipeline.instance_variable_get(:@ai)).to receive(:chat).and_return({
      "actions" => [
        {
          "text" => "move stealthily up to the goblins",
          "depends_on_index" => nil,
          "prerequisite" => nil,
          "abort_on_failed_prerequisite" => false
        },
        conditional_entry
      ],
      "reasoning" => "The spell only happens after the stealthy approach succeeds."
    }.to_json)
    allow(pipeline.instance_variable_get(:@ai)).to receive(:parse_json).and_return({
      "actions" => [
        {
          "text" => "move stealthily up to the goblins",
          "depends_on_index" => nil,
          "prerequisite" => nil,
          "abort_on_failed_prerequisite" => false
        },
        conditional_entry
      ]
    })

    actions = pipeline.send(:run_sequencer, "move stealthily up to the goblins, when I get there cast Ray of Frost")
    expect(actions.last).to include(
      "text" => "cast Ray of Frost on one of the goblins",
      "depends_on_index" => 0,
      "prerequisite" => "stealth_approach_succeeded",
      "abort_on_failed_prerequisite" => true
    )
  end
end
