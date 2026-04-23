# frozen_string_literal: true

require "rails_helper"

# C6 of the narrative facts plan — Loremaster wiring into the output fan-out.
#
# Covers the write-side claims that do not depend on the cutover (C10):
#   * Placement — fan-out batch contains a `loremaster` prompt.
#   * Single invocation per terminal narrative phase (write-side of
#     correctness claim #8) — Loremaster runs once regardless of action
#     queue depth, and is not invoked from `run_inter_action_context_update`.
#   * Lossy-on-failure — a raising `Lore::ApplyResults` surfaces through
#     `@log.report_error` + a `loremaster_failure` play_log without taking
#     the turn down.
#   * Idempotent reapply — two fan-outs for the same loop id leave a
#     single fact row (`partial unique index on (adventure_id,
#     introduced_at_loop_id, source_idx) WHERE source = 'loremaster'`).
#
# The read-side intra-queue staleness characterization (retrieval against
# a fact set that is not updated by Action 1 of the same message) lands
# in C10 — before the cutover, `sanity_checker_world` still reads
# micro-contexts so that assertion would be vacuous.
RSpec.describe "Stagehand — Loremaster wiring", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story)      { create(:story) }
  let(:user)       { create(:user) }
  let(:adventure)  { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline)   { build_pipeline(adventure) }

  def capture_narrative_phase_prompts
    captured = []
    allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:call_evaluator!).and_wrap_original do |orig, url, prompts, intention, phase:|
      captured << prompts if url.to_s.end_with?("/fan_out") && phase.to_s == "narrative_phase"
      orig.call(url, prompts, intention, phase: phase)
    end
    captured
  end

  describe "placement" do
    it "includes a loremaster prompt in the narrative-phase fan-out batch" do
      captured = capture_narrative_phase_prompts

      pipeline.run_prompt("I open the door carefully.")

      expect(captured).not_to be_empty
      first_batch = captured.first
      steps = first_batch.map { |p| p.dig(:meta, :step).to_s }
      expect(steps).to include("loremaster")
      expect(steps).to include("narrate")
    end

    it "does not include loremaster in the pause-time (inter-action) context update" do
      captured_phases = []
      allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:call_evaluator!).and_wrap_original do |orig, url, prompts, intention, phase:|
        if url.to_s.end_with?("/fan_out")
          steps = prompts.map { |p| p.dig(:meta, :step).to_s }
          captured_phases << { phase: phase.to_s, has_loremaster: steps.include?("loremaster") }
        end
        orig.call(url, prompts, intention, phase: phase)
      end

      pipeline.run_prompt("I open the door carefully.")

      non_narrative_phases = captured_phases.reject { |e| e[:phase] == "narrative_phase" }
      expect(non_narrative_phases.any? { |e| e[:has_loremaster] }).to be(false),
        "Loremaster leaked into a non-terminal phase: #{non_narrative_phases.select { |e| e[:has_loremaster] }}"
    end

    it "seeds the loremaster prompt with the active-facts window (empty by default for a fresh adventure)" do
      captured = capture_narrative_phase_prompts

      pipeline.run_prompt("I open the door carefully.")

      first_batch = captured.first
      loremaster_prompt = first_batch.find { |p| p.dig(:meta, :step).to_s == "loremaster" }
      expect(loremaster_prompt).to be_present
      expect(loremaster_prompt[:system_prompt]).to include("(none yet)")
    end
  end

  describe "write-side single-invocation per message (claim #8, write half)" do
    it "runs loremaster exactly once per player message regardless of action queue depth" do
      captured = capture_narrative_phase_prompts

      pipeline.run_prompt("I light my torch, then I open the door.")

      expect(captured.length).to eq(1),
        "Expected one narrative_phase fan-out per terminal player message; got #{captured.length}"
      loremaster_prompts = captured.first.select { |p| p.dig(:meta, :step).to_s == "loremaster" }
      expect(loremaster_prompts.length).to eq(1)
    end
  end

  describe "lossy-on-failure" do
    # `build_nulled_logger` (spec/support/pipeline_helpers.rb) stubs
    # `play_log!` and the ai_log helpers to null, so we cannot observe
    # the `loremaster_failure` row by querying PlayLog here. Instead we
    # assert on the stub receiving the call with the right arguments —
    # equivalent in contract: both `report_error` (Sentry path) and
    # `play_log!` (in-app event path) must fire when the apply raises,
    # and the turn must still narrate.
    it "reports to Sentry via log.report_error + emits loremaster_failure play_log and still narrates when ApplyResults raises" do
      allow(DungeonMaster::Lore::ApplyResults).to receive(:call).and_raise(StandardError, "simulated apply failure")

      reports = []
      allow(pipeline.log).to receive(:report_error).and_wrap_original do |orig, exception, **kwargs|
        reports << { exception: exception, kwargs: kwargs }
        orig.call(exception, **kwargs)
      end

      result = pipeline.run_prompt("I open the door carefully.")

      expect(result[:action]).to eq(:narrated)

      loremaster_report = reports.find do |entry|
        entry[:exception].is_a?(StandardError) &&
          entry[:kwargs].dig(:context, :step).to_s == "loremaster"
      end
      expect(loremaster_report).to be_present,
        "expected log.report_error with step: 'loremaster' but saw: #{reports.map { _1[:kwargs] }}"

      expect(pipeline.log).to have_received(:play_log!).with(
        "loremaster_failure",
        a_string_including("Loremaster apply_results failed"),
        parsed_response: hash_including(:error),
      )
    end
  end

  describe "idempotency under reapply" do
    it "does not duplicate facts when the same loop's narrative phase runs twice (partial unique index)" do
      loremaster_response = {
        "facts" => [
          { "text" => "the door is now open",
            "kind" => "event", "entities" => ["door"], "polarity" => "asserts" },
        ],
        "invalidates" => [],
        "reasoning" => "idempotency smoke",
      }

      allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:call_evaluator!).and_wrap_original do |orig, url, prompts, intention, phase:|
        results = orig.call(url, prompts, intention, phase: phase)
        if phase.to_s == "narrative_phase"
          Array(results).each do |r|
            if r.dig("meta", "step").to_s == "loremaster"
              r["parsed_response"] = loremaster_response
              r["raw_response"] = loremaster_response.to_json
            end
          end
        end
        results
      end

      allow_any_instance_of(DungeonMaster::AiClient).to receive(:embeddings)
        .and_return([Array.new(1536, 0.001)])

      pipeline.run_prompt("I open the door carefully.")
      last_loop = adventure.adventure_loops.order(:created_at).last

      # Drive the apply service a second time with the same (adventure, loop,
      # source_idx) triple — the partial unique index must make this a no-op.
      DungeonMaster::Lore::ApplyResults.call(
        adventure: adventure, loop: last_loop, log: pipeline.log, ai: pipeline.ai,
        result: loremaster_response,
      )

      count = AdventureNarrativeFact.where(
        adventure_id: adventure.id,
        introduced_at_loop_id: last_loop.id,
        source: "loremaster",
        source_idx: 0,
      ).count
      expect(count).to eq(1)
    end
  end
end
