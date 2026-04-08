require "rails_helper"

# Tests the per-action narration feature introduced by the action_queue config.
#
# Scenario: compound input splits into 3 actions:
#   1. "scout the corridor"  — non-mechanical, narrated immediately (progressive)
#   2. "pick the lock"       — needs_mechanics → Disable Device DC 15 → :awaiting_rolls
#   3. "push the door open"  — never reached in run_prompt; processed in run_rolls resume
#
# The evaluator stubs detect "lock" in the user_message to trigger mechanics.
RSpec.describe "DungeonMaster::PipelineEngine — per-action narration", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story)      { create(:story) }
  let(:user)       { create(:user) }
  let(:adventure)  { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }

  # Override sequencer + intake to route the compound action correctly.
  # Intake preserves action text; sequencer splits into 3 actions.
  let(:ai_responses) do
    AI_STEP_RESPONSES.merge(
      "intake" => {
        "sanitized_input" => "scout the corridor, pick the lock, and push the door open",
        "danger_score"    => 0,
        "reason"          => "Compound exploration action.",
        "is_dm_query"     => false
      }.to_json,
      "sequencer" => {
        "actions" => ["scout the corridor", "pick the lock", "push the door open"]
      }.to_json
    )
  end

  let(:narrative_calls) { [] }
  let(:on_narrative)    { ->(entry) { narrative_calls << entry } }
  let(:pipeline)        { build_pipeline(adventure, on_narrative: on_narrative) }

  # ── Test case 1: action_queue disabled — no splitting ──────────────────────
  describe "action_queue: false — sequencer bypassed, single narrative" do
    before do
      allow(DmConfig.instance).to receive(:get).and_call_original
      allow(DmConfig.instance).to receive(:get).with("action_queue").and_return(false)
    end

    # When the sequencer is bypassed, clean_input is treated as a single action.
    # Override intake to return a non-mechanical action so the evaluator doesn't
    # trigger mechanics (avoid "lock" in sanitized_input).
    let(:ai_responses) do
      AI_STEP_RESPONSES.merge(
        "intake" => {
          "sanitized_input" => "explore the dungeon corridor",
          "danger_score"    => 0,
          "reason"          => "Simple exploration.",
          "is_dm_query"     => false
        }.to_json
      )
    end

    subject(:result) do
      pipeline.run_prompt("scout the corridor and explore the area")
    end

    it "returns action: :narrated" do
      expect(result[:action]).to eq(:narrated)
    end

    it "includes a narrative string" do
      expect(result[:narrative]).to be_a(String).and be_present
    end

    it "does not fire the on_narrative callback (no per-action splitting)" do
      result
      expect(narrative_calls).to be_empty
    end
  end

  # ── Test case 2: action_queue: "progressive" — splits and halts at roll ────
  describe "action_queue: 'progressive' — 3 actions, halts at roll for action 2" do
    # Default DmConfig has action_queue: "progressive" — no override needed.

    subject(:result) do
      pipeline.run_prompt("scout the corridor, pick the lock, and push the door open")
    end

    it "returns action: :awaiting_rolls (pipeline halted at 'pick the lock')" do
      expect(result[:action]).to eq(:awaiting_rolls)
    end

    it "remaining_actions contains only 'push the door open'" do
      expect(result[:remaining_actions]).to eq(["push the door open"])
    end

    it "fires on_narrative exactly once (action 1 narrated before the halt)" do
      result
      expect(narrative_calls.size).to eq(1)
    end

    it "on_narrative entry has sequence_index: 0 (first action in turn)" do
      result
      expect(narrative_calls.first[:sequence_index]).to eq(0)
    end

    it "on_narrative entry has total_actions: 3" do
      result
      expect(narrative_calls.first[:total_actions]).to eq(3)
    end

    it "on_narrative entry has action_text: 'scout the corridor'" do
      result
      expect(narrative_calls.first[:action_text]).to eq("scout the corridor")
    end

    it "on_narrative entry includes a non-empty narrative string" do
      result
      expect(narrative_calls.first[:narrative]).to be_a(String).and be_present
    end
  end

  # ── Test case 3: roll resume — accumulated path covers remaining actions ───
  describe "roll resume after :awaiting_rolls" do
    # run_prompt is called once; result is memoised via awaiting_result.
    let(:awaiting_result) do
      pipeline.run_prompt("scout the corridor, pick the lock, and push the door open")
    end

    # Trigger run_prompt eagerly so the paused AdventureLoop row exists in the DB.
    let!(:_trigger_prompt) { awaiting_result }

    # Build metadata the way DungeonMasterService would after persisting the
    # roll_request message — string keys, intent deep-stringified.
    let(:metadata) do
      {
        "intent"               => awaiting_result[:intent].deep_stringify_keys,
        "mechanical_summaries" => Array(awaiting_result.dig(:merged, :mechanical_summaries)),
        "pending_npc_actions"  => Array(awaiting_result.dig(:merged, :npc_actions))
                                    .map { |a| a.is_a?(Hash) ? a.stringify_keys : a },
        "pending_consequences" => Array(awaiting_result.dig(:merged, :consequences))
                                    .map { |a| a.is_a?(Hash) ? a.stringify_keys : a },
        "remaining_actions"    => awaiting_result[:remaining_actions]
      }
    end

    let(:roll_results) { "Disable Device: rolled 18 (total 22 vs DC 15) — success" }

    subject(:resume_result) { pipeline.run_rolls(roll_results, metadata) }

    it "returns action: :narrated" do
      expect(resume_result[:action]).to eq(:narrated)
    end

    it "includes a narrative (accumulated path covers action 3 post-roll)" do
      expect(resume_result[:narrative]).to be_a(String).and be_present
    end

    it "does NOT fire additional on_narrative callbacks after the roll" do
      # on_narrative was called once during run_prompt (action 1 only).
      # run_rolls → run_remaining_queue → run_accumulated_narrative_phase — no per-action callbacks.
      calls_before = narrative_calls.size  # should be 1 from the earlier run_prompt
      resume_result
      expect(narrative_calls.size).to eq(calls_before)
    end

    it "writes pipeline_outcome to the paused AdventureLoop after resolution" do
      resume_result
      run_id = pipeline.instance_variable_get(:@log).registry_entry_uuid
      lock_loop = AdventureLoop.for_registry_entry(run_id)
                               .find_by(raw_action: "pick the lock")
      expect(lock_loop&.get("pipeline_outcome")).to be_present
    end
  end
end
