require "rails_helper"

# Tests the roll pause → resume flow.
# Phase 1: run_prompt with a mechanical action → :awaiting_rolls
# Phase 2: run_rolls with submitted values → :narrated
RSpec.describe "DungeonMaster::Pipeline — roll pause and resume", type: :service do
  include_context "with mocked ai"

  let(:story)         { create(:story) }
  let(:user)          { create(:user) }
  let(:adventure)     { create(:adventure, user: user, story: story) }
  # Mechanic step guards on @sheet — create an adventure_sheet so it loads one.
  let!(:adv_sheet)    { create(:adventure_sheet, adventure: adventure) }

  # Responses that produce a mechanical evaluation requiring a roll.
  let(:mechanical_ai_responses) do
    AI_STEP_RESPONSES.merge(
      "beacon" => {
        "affected"          => true,
        "needs_mechanics"   => true,
        "expand_scene"      => false,
        "destination"       => nil,
        "rules_needed"      => ["Disable Device"],
        "transition"        => nil,
        "macro_significant" => false,
        "domain_interpretation" => "Player tries to pick the lock — requires Disable Device check."
      }.to_json,

      "mechanical_evaluation" => {
        "player_rolls"       => [{ "skill" => "Disable Device", "type" => "skill_check",
                                   "dc" => 15, "domain" => "exploration" }],
        "npc_actions"        => [],
        "consequences"       => [],
        "mechanical_summary" => "Disable Device DC 15 required."
      }.to_json,

      "roll_qualifier" => {
        "player_rolls" => [{ "skill" => "Disable Device", "type" => "skill_check",
                             "dc" => 15, "domain" => "exploration",
                             "take_10_eligible" => false, "take_10_value" => nil }]
      }.to_json,

      "sanity_checker_world" => { "consistent" => true, "reason" => nil, "dm_message" => nil }.to_json,
      "sanity_checker"       => { "consistent" => true, "reason" => nil, "dm_message" => nil, "allowed" => true }.to_json
    )
  end

  before do
    allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
      instance.instance_variable_set(:@last_parse_status, "success")
      instance.instance_variable_set(:@last_model_used, "gpt-4o-mini-test")
      instance.instance_variable_set(:@last_usage, {})
      mechanical_ai_responses.fetch(kwargs[:step_name].to_s, '{"result":"ok"}')
    end
  end

  describe "phase 1 — run_prompt returns :awaiting_rolls for mechanical actions" do
    subject(:result) { build_pipeline(adventure).run_prompt("I try to pick the lock.") }

    it "returns action: :awaiting_rolls" do
      expect(result[:action]).to eq(:awaiting_rolls)
    end

    it "includes intent data for resumption" do
      expect(result[:intent]).to be_present
    end

    it "includes merged mechanical data" do
      expect(result[:merged]).to be_present
      expect(result[:merged][:player_rolls]).to be_an(Array).and be_present
    end
  end

  describe "phase 2 — run_rolls completes resolution" do
    # Build a minimal metadata hash as the service would persist between phases.
    let(:metadata) do
      {
        "intent" => {
          "intention"         => "try to pick the lock",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["exploration"],
          "primary_context"   => "exploration",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Disable Device DC 15 required."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => []
      }
    end

    let(:roll_results) { "Disable Device: rolled 18 (total 22 vs DC 15) — success" }

    # Build the pipeline once so we can read its pipeline_run_id and create the
    # matching paused AdventureLoop row that restore_paused_loop! expects.
    let(:pipeline) { build_pipeline(adventure) }
    let!(:paused_loop) do
      AdventureLoop.create!(
        adventure:        adventure,
        pipeline_run_id:  pipeline.instance_variable_get(:@log).pipeline_run_id,
        sequence_index:   0,
        raw_action:       "try to pick the lock",
        player_intent:    "try to pick the lock",
        status:           "paused"
      )
    end

    subject(:result) { pipeline.run_rolls(roll_results, metadata) }

    it "returns action: :narrated" do
      expect(result[:action]).to eq(:narrated)
    end

    it "includes a narrative" do
      expect(result[:narrative]).to be_a(String).and be_present
    end
  end
end
