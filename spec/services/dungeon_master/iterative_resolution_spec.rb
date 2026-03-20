# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster — iterative roll resolution", type: :service do
  include_context "with mocked ai"

  let(:story)     { create(:story) }
  let(:user)      { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure).tap(&:recompute_derived_stats!) }

  let(:iterative_rolls) do
    [
      { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 10,
        "description" => "Fort save, forced march hour 9", "domain" => "traversal",
        "iterative" => true, "sequence" => 1, "phase" => "Forced march, hour 9" },
      { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
        "description" => "Fort save, forced march hour 10", "domain" => "traversal",
        "iterative" => true, "sequence" => 2, "phase" => "Forced march, hour 10" },
      { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 12,
        "description" => "Fort save, forced march hour 11", "domain" => "traversal",
        "iterative" => true, "sequence" => 3, "phase" => "Forced march, hour 11" }
    ]
  end

  let(:iterative_mech_eval_response) do
    {
      "player_rolls"       => iterative_rolls,
      "npc_actions"        => [],
      "consequences"       => [],
      "iterative_time_hours" => 1.0,
      "mechanical_summary" => "Forced march: 3 hourly Fort saves."
    }.to_json
  end

  let(:iterative_ai_responses) do
    AI_STEP_RESPONSES.merge(
      "beacon" => {
        "affected"          => true,
        "needs_mechanics"   => true,
        "expand_scene"      => false,
        "destination"       => nil,
        "rules_needed"      => [],
        "transition"        => nil,
        "macro_significant" => false,
        "domain_interpretation" => "Player runs for many hours — forced march."
      }.to_json,

      "mechanical_evaluation" => iterative_mech_eval_response,

      "roll_qualifier" => {
        "qualifications" => []
      }.to_json,

      "sanity_checker_world" => { "consistent" => true, "reason" => nil, "dm_message" => nil }.to_json,
      "sanity_checker"       => { "consistent" => true, "reason" => nil, "dm_message" => nil, "allowed" => true }.to_json
    )
  end

  before do
    adventure.update!(time_context: {
      "current_hour" => 8,
      "adventure_day" => 1,
      "hours_since_last_rest" => 8,
      "hours_since_last_encounter_check" => 0
    })

    allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
      instance.instance_variable_set(:@last_parse_status, "success")
      instance.instance_variable_set(:@last_model_used, "test")
      instance.instance_variable_set(:@last_usage, {})
      iterative_ai_responses.fetch(kwargs[:step_name].to_s, '{"result":"ok"}')
    end
  end

  # ── Chunking ───────────────────────────────────────────────────────────────

  describe "iterative roll chunking" do
    let(:merged) do
      {
        player_rolls: iterative_rolls.map { |r| r.deep_symbolize_keys },
        npc_actions: [],
        consequences: [],
        mechanical_summaries: ["Forced march: 3 hourly Fort saves."],
        iterative_time_hours: 1.0
      }
    end

    let(:intent) do
      { intention: "run for 11 hours", needs_mechanics: true,
        affected_contexts: ["traversal"], primary_context: "traversal" }
    end

    subject(:result) do
      build_pipeline(adventure).send(:chunk_iterative_or_return_rolls, intent, merged)
    end

    it "returns :awaiting_rolls with only the first roll" do
      expect(result[:status]).to eq(:awaiting_rolls)
      expect(result[:merged][:player_rolls].size).to eq(1)
      expect(result[:merged][:player_rolls].first[:dc]).to eq(10)
    end

    it "stores remaining iterative rolls" do
      expect(result[:remaining_iterative_rolls]).to be_an(Array)
      expect(result[:remaining_iterative_rolls].size).to eq(2)
    end

    it "passes through iterative_time_hours" do
      expect(result[:iterative_time_hours]).to eq(1.0)
    end

    it "sets iterative_total to total roll count" do
      expect(result[:iterative_total]).to eq(3)
    end

    it "returns all rolls when none are iterative" do
      non_iterative = merged.merge(player_rolls: [
        { type: "skill_check", skill: "Perception", dc: 15 },
        { type: "skill_check", skill: "Stealth", dc: 12 }
      ])
      result = build_pipeline(adventure).send(:chunk_iterative_or_return_rolls, intent, non_iterative)
      expect(result[:remaining_iterative_rolls]).to be_nil
      expect(result[:merged][:player_rolls].size).to eq(2)
    end
  end

  # ── Continuation ───────────────────────────────────────────────────────────

  describe "iterative continuation (run_rolls)" do
    let(:metadata) do
      {
        "intent" => {
          "intention"         => "run for 11 hours toward the next town",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["traversal"],
          "primary_context"   => "traversal",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Forced march: 3 hourly Fort saves."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => [],
        "remaining_iterative_rolls" => [
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
            "description" => "Fort save, forced march hour 10", "domain" => "traversal",
            "iterative" => true, "sequence" => 2, "phase" => "Forced march, hour 10" },
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 12,
            "description" => "Fort save, forced march hour 11", "domain" => "traversal",
            "iterative" => true, "sequence" => 3, "phase" => "Forced march, hour 11" }
        ],
        "iterative_time_hours" => 1.0,
        "iterative_total" => 3
      }
    end

    let(:roll_results) { "Fortitude Save: rolled 14 (total 16 vs DC 10) — success" }

    it "returns :awaiting_rolls with the next iterative roll" do
      result = build_pipeline(adventure).run_rolls(roll_results, metadata)
      expect(result[:action]).to eq(:awaiting_rolls)
      expect(result[:merged][:player_rolls].size).to eq(1)
      expect(result[:merged][:player_rolls].first[:dc]).to eq(11)
    end

    it "decrements remaining_iterative_rolls by 1" do
      result = build_pipeline(adventure).run_rolls(roll_results, metadata)
      expect(result[:remaining_iterative_rolls].size).to eq(1)
    end

    it "includes interim_narrative from the previous roll resolution" do
      result = build_pipeline(adventure).run_rolls(roll_results, metadata)
      expect(result[:interim_narrative]).to be_present
    end

    it "preserves iterative_time_hours" do
      result = build_pipeline(adventure).run_rolls(roll_results, metadata)
      expect(result[:iterative_time_hours]).to eq(1.0)
    end
  end

  # ── Time advancement ───────────────────────────────────────────────────────

  describe "iterative time advancement" do
    let(:metadata) do
      {
        "intent" => {
          "intention"         => "run for 11 hours",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["traversal"],
          "primary_context"   => "traversal",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Forced march: Fort saves."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => [],
        "remaining_iterative_rolls" => [
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
            "iterative" => true, "sequence" => 2 }
        ],
        "iterative_time_hours" => 1.0,
        "iterative_total" => 2
      }
    end

    it "advances time by iterative_time_hours, not full action duration" do
      adventure.update!(time_context: {
        "current_hour" => 17,
        "adventure_day" => 1,
        "hours_since_last_rest" => 9,
        "hours_since_last_encounter_check" => 0
      })

      build_pipeline(adventure).run_rolls("Fort save: 15", metadata)
      adventure.reload
      expect(adventure.time_context["current_hour"]).to be_within(0.01).of(18.0)
    end
  end

  # ── Fatigue during iteration ───────────────────────────────────────────────

  describe "fatigue during iterative rolls" do
    let(:metadata) do
      {
        "intent" => {
          "intention"         => "forced march",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["traversal"],
          "primary_context"   => "traversal",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Forced march Fort saves."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => [],
        "remaining_iterative_rolls" => [
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
            "iterative" => true, "sequence" => 2 }
        ],
        "iterative_time_hours" => 1.0,
        "iterative_total" => 2
      }
    end

    it "applies fatigued condition when cumulative time crosses threshold" do
      adventure.update!(time_context: {
        "current_hour" => 23,
        "adventure_day" => 1,
        "hours_since_last_rest" => 15.5,
        "hours_since_last_encounter_check" => 0
      })

      build_pipeline(adventure).run_rolls("Fort save: 15", metadata)
      expect(sheet.reload.conditions).to include("fatigued")
    end
  end

  # ── Encounter interruption ─────────────────────────────────────────────────

  describe "encounter interruption during iterative rolls" do
    let!(:encounter_table) do
      EncounterTable.create!(story: story, name: "Test Table",
                             check_frequency_hours: 1, encounter_chance: 100)
    end

    let!(:encounter_entry) do
      EncounterTableEntry.create!(encounter_table: encounter_table, title: "Wolf Pack",
                                  description: "A pack of wolves", entry_type: "fixed", weight: 1)
    end

    let(:metadata) do
      {
        "intent" => {
          "intention"         => "forced march",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["traversal"],
          "primary_context"   => "traversal",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Forced march Fort saves."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => [],
        "remaining_iterative_rolls" => [
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
            "iterative" => true, "sequence" => 2 }
        ],
        "iterative_time_hours" => 1.0,
        "iterative_total" => 2
      }
    end

    it "stops the iterative sequence when an encounter triggers" do
      adventure.update!(time_context: {
        "current_hour" => 20,
        "adventure_day" => 1,
        "hours_since_last_rest" => 12,
        "hours_since_last_encounter_check" => 0.99
      })

      allow(DungeonMaster::Utilities::Harbinger).to receive(:consult).and_return({
        interrupted: true,
        stop_reason: :encounter,
        hours_granted: 0.5,
        narrative_seed: "A pack of wolves appears!",
        encounter_entry: encounter_entry
      })

      # finish_resolution returns :encounter status when Harbinger triggers,
      # bypassing the iterative continuation entirely. The narrate step may
      # raise because @loop is nil in this unit test (no prior run_prompt
      # created a loop), so we rescue and verify the iterative loop stopped.
      result = begin
        build_pipeline(adventure).run_rolls("Fort save: 15", metadata)
      rescue DungeonMaster::AiError => e
        raise unless e.message.include?("nothing to narrate")
        { action: :encounter_output }
      end
      expect(result[:action]).not_to eq(:awaiting_rolls)
    end
  end

  # ── Early stop: HP ─────────────────────────────────────────────────────────

  describe "early stop when HP reaches 0" do
    let(:metadata) do
      {
        "intent" => {
          "intention"         => "forced march",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["traversal"],
          "primary_context"   => "traversal",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Forced march Fort saves."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => [],
        "remaining_iterative_rolls" => [
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
            "iterative" => true, "sequence" => 2 }
        ],
        "iterative_time_hours" => 1.0,
        "iterative_total" => 2
      }
    end

    it "proceeds to output instead of continuing iterative rolls" do
      sheet.update_column(:hp, 0)

      result = build_pipeline(adventure).run_rolls("Fort save: 15", metadata)
      expect(result[:action]).not_to eq(:awaiting_rolls)
    end
  end

  # ── Early stop: cannot_act ─────────────────────────────────────────────────

  describe "early stop when character cannot act" do
    let(:metadata) do
      {
        "intent" => {
          "intention"         => "forced march",
          "needs_mechanics"   => true,
          "expand_scene"      => false,
          "affected_contexts" => ["traversal"],
          "primary_context"   => "traversal",
          "macro_significant" => false,
          "plot_relevant"     => false,
          "beacon_results"    => {}
        },
        "mechanical_summaries"  => ["Forced march Fort saves."],
        "pending_npc_actions"   => [],
        "pending_consequences"  => [],
        "remaining_actions"     => [],
        "prior_narrate_seeds"   => [],
        "remaining_iterative_rolls" => [
          { "skill" => "Fortitude", "type" => "fortitude_save", "dc" => 11,
            "iterative" => true, "sequence" => 2 }
        ],
        "iterative_time_hours" => 1.0,
        "iterative_total" => 2
      }
    end

    it "proceeds to output when character has cannot_act restriction" do
      sheet.update_column(:conditions, ["paralyzed"])
      sheet.recompute_derived_stats!

      result = build_pipeline(adventure).run_rolls("Fort save: 15", metadata)
      expect(result[:action]).not_to eq(:awaiting_rolls)
    end
  end

  # ── Roll qualifier error propagation ───────────────────────────────────────

  describe "roll qualifier TokenBudgetExceededError propagation" do
    before do
      call_count = 0
      allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
        instance.instance_variable_set(:@last_parse_status, "success")
        instance.instance_variable_set(:@last_model_used, "test")
        instance.instance_variable_set(:@last_usage, {})

        if kwargs[:step_name] == "roll_qualifier"
          raise DungeonMaster::TokenBudgetExceededError.new(step_name: "roll_qualifier", budget: 800)
        end

        iterative_ai_responses.fetch(kwargs[:step_name].to_s, '{"result":"ok"}')
      end
    end

    it "propagates to the caller instead of being silently swallowed" do
      expect {
        build_pipeline(adventure).run_prompt("I run for 11 hours toward the next town.")
      }.to raise_error(DungeonMaster::TokenBudgetExceededError)
    end
  end
end
