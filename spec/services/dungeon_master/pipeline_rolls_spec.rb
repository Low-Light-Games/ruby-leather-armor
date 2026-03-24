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
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => []
      }
    end

    let(:roll_results) { "Disable Device: rolled 18 (total 22 vs DC 15) — success" }

    subject(:result) { build_pipeline(adventure).run_rolls(roll_results, metadata) }

    it "returns action: :narrated" do
      expect(result[:action]).to eq(:narrated)
    end

    it "includes a narrative" do
      expect(result[:narrative]).to be_a(String).and be_present
    end

    it "writes pipeline_outcome to the AdventureLoop row after resolution" do
      result
      paused_loop.reload
      expect(paused_loop.get("pipeline_outcome")).to be_present
    end
  end

  describe "run_accumulated_output_phase — pipeline_outcome DB assembly" do
    # Directly exercise the DB query that assembles the combined narration seed
    # from AdventureLoop#pipeline_outcome rows ordered by sequence_index.

    let(:pipeline) { build_pipeline(adventure) }
    let(:run_id)   { pipeline.instance_variable_get(:@log).pipeline_run_id }

    def make_loop(seq, outcome)
      AdventureLoop.create!(
        adventure:       adventure,
        pipeline_run_id: run_id,
        sequence_index:  seq,
        raw_action:      "action #{seq}",
        player_intent:   "action #{seq}",
        status:          "resolved",
        data:            { "pipeline_outcome" => outcome }
      )
    end

    context "with a single loop row" do
      before { make_loop(0, "The door swings open.") }

      it "passes the outcome as the narration seed" do
        narrate_calls = []
        allow_any_instance_of(DungeonMaster::Pipeline).to receive(:run_narrate).and_wrap_original do |original, seed, **kwargs|
          narrate_calls << seed
          original.call(seed, **kwargs)
        end

        pipeline.send(:run_accumulated_output_phase,
          [{ status: :resolved, intent: { intention: "open door", affected_contexts: [],
                                          macro_significant: false, plot_relevant: false,
                                          primary_context: "exploration", beacon_results: {} } }])

        expect(narrate_calls.first).to eq("The door swings open.")
      end
    end

    context "with multiple loop rows (compound action)" do
      before do
        make_loop(0, "You pick up the torch.")
        make_loop(1, "You push open the door.")
      end

      it "joins outcomes in sequence_index order with 'Then:' separator" do
        narrate_calls = []
        allow_any_instance_of(DungeonMaster::Pipeline).to receive(:run_narrate).and_wrap_original do |original, seed, **kwargs|
          narrate_calls << seed
          original.call(seed, **kwargs)
        end

        pipeline.send(:run_accumulated_output_phase,
          [{ status: :resolved, intent: { intention: "pick up torch then open door",
                                          affected_contexts: [], macro_significant: false,
                                          plot_relevant: false, primary_context: "exploration",
                                          beacon_results: {} } },
           { status: :resolved, intent: { intention: "pick up torch then open door",
                                          affected_contexts: [], macro_significant: false,
                                          plot_relevant: false, primary_context: "exploration",
                                          beacon_results: {} } }])

        expect(narrate_calls.first).to eq("You pick up the torch.\n\nThen: You push open the door.")
      end
    end

    context "with no pipeline_outcome on any loop row" do
      before { make_loop(0, nil) }

      it "passes nil seed (narrate will raise, which is expected behaviour)" do
        narrate_calls = []
        allow_any_instance_of(DungeonMaster::Pipeline).to receive(:run_narrate).and_wrap_original do |original, seed, **kwargs|
          narrate_calls << seed
          original.call(seed, **kwargs)
        end

        expect {
          pipeline.send(:run_accumulated_output_phase,
            [{ status: :resolved, intent: { intention: "do something",
                                            affected_contexts: [], macro_significant: false,
                                            plot_relevant: false, primary_context: "exploration",
                                            beacon_results: {} } }])
        }.to raise_error(DungeonMaster::AiError, /without an outcome/)

        expect(narrate_calls.first).to be_nil
      end
    end
  end
end
