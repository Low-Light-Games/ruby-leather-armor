require "rails_helper"

# Tests the roll pause → resume flow.
# Phase 1: run_prompt with a mechanical action → :awaiting_rolls
# Phase 2: run_rolls with submitted values → :narrated
RSpec.describe "DungeonMaster::PipelineEngine — roll pause and resume", type: :service do
  include_context "with mocked ai"
  # Evaluator stubs intercept /fan_out and /sequential. "lock" in the action
  # text causes the exploration beacon to flag needs_mechanics: true and
  # mech_eval to return a Disable Device DC 15 roll.
  include_context "with evaluator stubs"

  let(:story)         { create(:story) }
  let(:user)          { create(:user) }
  let(:adventure)     { create(:adventure, user: user, story: story) }
  # Mechanic step guards on @sheet — create an adventure_sheet so it loads one.
  let!(:adv_sheet)    { create(:adventure_sheet, adventure: adventure) }

  describe "phase 1 — run_prompt returns :awaiting_rolls for mechanical actions" do
    # Override intake + sequencer so "lock" reaches the evaluator stubs,
    # which then mark exploration needs_mechanics: true → Disable Device DC 15.
    let(:ai_responses) do
      AI_STEP_RESPONSES.merge(
        "intake"    => { "sanitized_input" => "try to pick the lock",
                         "danger_score" => 0, "reason" => "Lock-picking attempt.",
                         "is_dm_query" => false }.to_json,
        "sequencer" => { "actions" => ["try to pick the lock"] }.to_json,
        "sanity_checker_world" => { "consistent" => true, "reason" => nil, "dm_message" => nil }.to_json,
        "sanity_checker"       => { "consistent" => true, "reason" => nil, "dm_message" => nil,
                                    "allowed" => true }.to_json
      )
    end

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
          "macro_significant" => false,
          "domain_results"    => {}
        },
        "mechanical_summaries"  => ["Disable Device DC 15 required."],
        "roll_requests"         => [{ "type" => "skill_check", "skill" => "Disable Device", "dc" => 15, "description" => "Disable Device DC 15 required." }],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => []
      }
    end

    let(:roll_results) { "Disable Device: rolled 18 (total 22 vs DC 15) — success" }

    # Build the pipeline once so we can read its registry_entry_uuid and create the
    # matching paused AdventureLoop row that restore_paused_loop! expects.
    let(:pipeline) { build_pipeline(adventure) }
    let!(:paused_loop) do
      AdventureLoop.create!(
        adventure:             adventure,
        registry_entry_uuid:   pipeline.instance_variable_get(:@log).registry_entry_uuid,
        sequence_index:   0,
        raw_action:       "try to pick the lock",
        player_intent:    "try to pick the lock",
        status:           "paused"
      )
    end

    let(:submitted_rolls) { [{ roll_value: 18, roll_description: "Disable Device DC 15 required." }] }

    subject(:result) { pipeline.run_rolls(roll_results, metadata, submitted_rolls: submitted_rolls) }

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

  describe "run_accumulated_narrative_phase — pipeline_outcome DB assembly" do
    # Directly exercise the DB query that assembles the combined narration seed
    # from AdventureLoop#pipeline_outcome rows ordered by sequence_index.

    let(:pipeline) { build_pipeline(adventure) }
    let(:run_id)   { pipeline.instance_variable_get(:@log).registry_entry_uuid }

    def make_loop(seq, outcome)
      AdventureLoop.create!(
        adventure:           adventure,
        registry_entry_uuid: run_id,
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
        allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:narrate_evaluator_prompt).and_wrap_original do |original, pipeline_ctx|
          narrate_calls << pipeline_ctx.combined_seed
          original.call(pipeline_ctx)
        end

        pipeline.send(:run_accumulated_narrative_phase,
          [{ status: :resolved, intent: { intention: "open door", affected_contexts: [],
                                          macro_significant: false, domain_results: {} } }])

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
        allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:narrate_evaluator_prompt).and_wrap_original do |original, pipeline_ctx|
          narrate_calls << pipeline_ctx.combined_seed
          original.call(pipeline_ctx)
        end

        pipeline.send(:run_accumulated_narrative_phase,
          [{ status: :resolved, intent: { intention: "pick up torch then open door",
                                          affected_contexts: [], macro_significant: false,
                                          domain_results: {} } },
           { status: :resolved, intent: { intention: "pick up torch then open door",
                                          affected_contexts: [], macro_significant: false,
                                          domain_results: {} } }])

        expect(narrate_calls.first).to eq("You pick up the torch.\n\nThen: You push open the door.")
      end
    end

    context "with no pipeline_outcome on any loop row" do
      before { make_loop(0, nil) }

      it "passes nil seed (narrate will raise, which is expected behaviour)" do
        narrate_calls = []
        allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:narrate_evaluator_prompt).and_wrap_original do |original, pipeline_ctx|
          narrate_calls << pipeline_ctx.combined_seed
          original.call(pipeline_ctx)
        end

        expect {
          pipeline.send(:run_accumulated_narrative_phase,
            [{ status: :resolved, intent: { intention: "do something",
                                            affected_contexts: [], macro_significant: false,
                                            domain_results: {} } }])
        }.to raise_error(DungeonMaster::AiError, /without an outcome/)

        expect(narrate_calls.first).to be_nil
      end
    end
  end
end
