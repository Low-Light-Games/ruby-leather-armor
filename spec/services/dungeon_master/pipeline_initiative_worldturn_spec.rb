# frozen_string_literal: true

require "rails_helper"

# Regression specs for initiative/roll-resume terminal-state propagation.
#
# Covers two bugs that existed before the fix:
#   A) run_initiative passed base_mutations (pre-world-turn) to run_remaining_queue,
#      and did not stop the queue when the player was killed by NPCs going first.
#   B) continue_or_narrate_after_resume (used by run_rolls) continued the queue
#      even when the accumulated row carried :player_death / :player_incapacitated.
RSpec.describe "DungeonMaster::PipelineEngine — initiative + world-turn terminal propagation", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end
  let(:pipeline) { build_pipeline(adventure) }

  def paused_loop_for(pipeline, action_text)
    AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: pipeline.instance_variable_get(:@log).registry_entry_uuid,
      sequence_index: 0,
      raw_action: action_text,
      player_intent: action_text,
      status: "paused"
    )
  end

  def base_initiative_metadata(overrides = {})
    {
      "intent" => {
        "intention" => "I attack the goblin",
        "expand_scene" => false,
        "affected_contexts" => ["combat"],
        "macro_significant" => false,
        "domain_results" => {}
      },
      "mutations" => {},
      "creature_data" => [],
      "pending_opening_merged" => nil,
      "remaining_actions" => []
    }.merge(overrides)
  end

  describe "run_initiative — Fix A: post-world-turn mutations and terminal short-circuit" do
    # Stub compute_combat_initialization to make NPCs go first so maybe_run_world_turn is called.
    let(:npc_first_combat_data) do
      {
        "active" => true,
        "round" => 1,
        "current_turn" => "Goblin",
        "turn_order" => ["Goblin", "Player"],
        "participants" => [
          { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 5,
            "initiative" => 20, "conditions" => [], "creature_sheet_id" => nil },
          { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10,
            "initiative" => 15, "conditions" => [] }
        ],
        "terrain_notes" => nil,
      }
    end

    before do
      allow(DungeonMaster::Utilities::Warmaster).to receive(:compute_combat_initialization)
        .and_return(npc_first_combat_data)
    end

    context "when NPCs go first and kill the player" do
      it "does not continue the remaining queue and narrates the terminal outcome" do
        paused_loop_for(pipeline, "I attack the goblin")
        meta = base_initiative_metadata("remaining_actions" => ["I run away"])

        allow(pipeline).to receive(:maybe_run_world_turn) do |result|
          result.merge(player_death: true, mutations: { "combat_context" => { "active" => false } })
        end

        expect(pipeline).not_to receive(:run_remaining_queue)
        allow(pipeline).to receive(:run_accumulated_narrative_phase).and_return({ action: :narrated, narrative: "stub" })

        pipeline.run_initiative(15, meta)
      end
    end

    context "when NPCs go first and player survives" do
      it "passes post-world-turn (not base) mutations to the remaining queue" do
        paused_loop_for(pipeline, "I attack the goblin")
        enriched_mutations = { "combat_context" => { "active" => true, "round" => 2 } }
        meta = base_initiative_metadata("remaining_actions" => ["I strike again"])

        allow(pipeline).to receive(:maybe_run_world_turn) do |result|
          result.merge(mutations: enriched_mutations)
        end

        captured = nil
        allow(pipeline).to receive(:run_remaining_queue).and_wrap_original do |orig, remaining, **kwargs|
          captured = kwargs[:initial_accumulated]
          { action: :narrated, narrative: "stub" }
        end

        pipeline.run_initiative(15, meta)
        expect(captured).to match([hash_including(mutations: enriched_mutations)])
      end
    end
  end

  describe "continue_or_narrate_after_resume — Fix B: terminal state skips queue" do
    # Use a fully stubbed narrate to avoid real pipeline execution.
    before do
      allow(pipeline).to receive(:run_accumulated_narrative_phase).and_return({ action: :narrated, narrative: "stub" })
    end

    it "does not call run_remaining_queue when player_death is set" do
      expect(pipeline).not_to receive(:run_remaining_queue)

      pipeline.send(:continue_or_narrate_after_resume,
        { "remaining_actions" => ["I flee"] },
        accumulated_row: {
          status: :resolved,
          intent: { intention: "attack", affected_contexts: [], macro_significant: false, domain_results: {} },
          mutations: {},
          player_death: true
        },
        only_continue_if_resolved: true)
    end

    it "does not call run_remaining_queue when player_incapacitated is set" do
      expect(pipeline).not_to receive(:run_remaining_queue)

      pipeline.send(:continue_or_narrate_after_resume,
        { "remaining_actions" => ["I flee"] },
        accumulated_row: {
          status: :resolved,
          intent: { intention: "attack", affected_contexts: [], macro_significant: false, domain_results: {} },
          mutations: {},
          player_incapacitated: true
        },
        only_continue_if_resolved: true)
    end

    it "continues the queue when the player is alive and status is resolved" do
      expect(pipeline).to receive(:run_remaining_queue).and_return({ action: :narrated, narrative: "stub" })

      pipeline.send(:continue_or_narrate_after_resume,
        { "remaining_actions" => ["I flee"] },
        accumulated_row: {
          status: :resolved,
          intent: { intention: "attack", affected_contexts: [], macro_significant: false, domain_results: {} },
          mutations: {}
        },
        only_continue_if_resolved: true)
    end
  end

  describe "combat-start opening action after initiative" do
    let(:combat_data) do
      {
        "active" => true,
        "round" => 1,
        "current_turn" => "Player",
        "turn_order" => ["Player", "Goblin"],
        "participants" => [
          { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 15, "conditions" => [] },
          { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 5, "initiative" => 10, "conditions" => [], "creature_sheet_id" => 123 }
        ],
        "terrain_notes" => nil,
      }
    end

    before do
      allow(DungeonMaster::Utilities::Warmaster).to receive(:compute_combat_initialization)
        .and_return(combat_data)
    end

    it "stores pending opening merged data in initiative request metadata" do
      result = {
        creature_data: [{ "name" => "Goblin", "creature_sheet_id" => 123, "initiative" => 10 }],
        intent: { intention: "I cast Ray of Frost", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
        mutations: {},
        opener_outcome: "Fig charges first.",
        merged: { player_rolls: [{ type: "attack_roll", dc: 12 }], npc_actions: [], consequences: [], mechanical_summaries: ["attack"], bonus_context: { flank: false } },
        remaining_actions: []
      }

      meta = DungeonMaster::AdventurePlay::InitiativeRequestMetadata.for_awaiting_initiative(result)
      stored = meta["pending_opening_merged"] || meta[:pending_opening_merged]
      expect(stored).to include("player_rolls", "mechanical_summaries", "bonus_context")
      expect(meta[:opener_outcome]).to eq("Fig charges first.")
    end

    it "returns awaiting_rolls after initiative when an opening action still needs rolls" do
      paused_loop_for(pipeline, "I cast Ray of Frost")
      meta = base_initiative_metadata(
        "pending_opening_merged" => {
          "player_rolls" => [{ "type" => "attack_roll", "dc" => 12, "description" => "Ray of Frost vs goblin" }],
          "npc_actions" => [],
          "consequences" => [],
          "mechanical_summaries" => ["Ray of Frost requires an attack roll."]
        }
      )

      expect(pipeline).not_to receive(:maybe_run_world_turn)

      result = pipeline.run_initiative(15, meta)
      expect(result[:action]).to eq(:awaiting_rolls)
      expect(result[:merged][:player_rolls]).not_to be_empty
    end

    it "round-trips extra merged keys through initiative metadata" do
      meta = base_initiative_metadata(
        "pending_opening_merged" => {
          "player_rolls" => [],
          "npc_actions" => [],
          "consequences" => [],
          "mechanical_summaries" => [],
          "bonus_context" => { "flank" => false }
        }
      )

      restored = pipeline.send(:restore_opening_action_merged, meta)
      expect(restored[:bonus_context]).to eq({ flank: false })
    end

    it "prefers the current result remaining_actions over stale roll metadata when pausing for initiative" do
      paused_loop_for(pipeline, "I cast Ray of Frost")
      allow(pipeline).to receive(:battlefield_roll_version_mismatch?).and_return(false)
      allow(DungeonMaster::Rolls::PlayerRolls).to receive(:tag_roll_resolution!)

      intent = { intention: "I cast Ray of Frost", affected_contexts: ["combat"], macro_significant: false, domain_results: {} }
      merged = { player_rolls: [{ type: "attack_roll", dc: 12 }], npc_actions: [], consequences: [], mechanical_summaries: ["attack"] }
      result = {
        status: :awaiting_initiative,
        intent: intent,
        merged: merged,
        pending_opening_merged: merged,
        creature_data: [{ "name" => "Goblin", "creature_sheet_id" => 123, "initiative" => 10 }],
        mutations: {},
        remaining_actions: []
      }

      allow(pipeline).to receive(:restore_roll_pause_inputs).and_return([intent, merged])
      allow(pipeline).to receive(:finish_resolution).and_return(result)
      allow(pipeline).to receive(:run_context_updates_at_encounter_pause)

      resumed = pipeline.run_rolls("Rolled 14 for: attack", {
        "remaining_actions" => [{ "text" => "stale opener replay" }]
      })

      expect(resumed[:action]).to eq(:awaiting_initiative)
      expect(resumed[:remaining_actions]).to eq([])
      expect(resumed[:pending_opening_merged]).to include(:player_rolls, :mechanical_summaries)
    end

    it "round-trips structured remaining_actions through roll pause and initiative pause together" do
      paused_loop_for(pipeline, "I cast Ray of Frost")
      allow(pipeline).to receive(:battlefield_roll_version_mismatch?).and_return(false)
      allow(DungeonMaster::Rolls::PlayerRolls).to receive(:tag_roll_resolution!)

      intent = { intention: "I cast Ray of Frost", affected_contexts: ["combat"], macro_significant: false, domain_results: {} }
      merged = { player_rolls: [{ type: "attack_roll", dc: 12 }], npc_actions: [], consequences: [], mechanical_summaries: ["attack"] }
      structured_remaining = [{
        "text" => "drink a potion",
        "depends_on_index" => nil,
        "prerequisite" => nil,
        "abort_on_failed_prerequisite" => false
      }]
      result = {
        status: :awaiting_initiative,
        intent: intent,
        merged: merged,
        pending_opening_merged: merged,
        creature_data: [{ "name" => "Goblin", "creature_sheet_id" => 123, "initiative" => 10 }],
        mutations: {},
        remaining_actions: structured_remaining
      }

      allow(pipeline).to receive(:restore_roll_pause_inputs).and_return([intent, merged])
      allow(pipeline).to receive(:finish_resolution).and_return(result)
      allow(pipeline).to receive(:run_context_updates_at_encounter_pause)

      resumed = pipeline.run_rolls("Rolled 14 for: attack", {
        "remaining_actions" => [{ "text" => "stale opener replay" }]
      })
      meta = DungeonMaster::AdventurePlay::InitiativeRequestMetadata.for_awaiting_initiative(resumed)

      expect(meta[:remaining_actions]).to eq(structured_remaining)
      expect(meta[:pending_opening_merged]).to include("player_rolls", "mechanical_summaries")
    end

    it "lets only pre-player NPCs act after a resolved opener when NPCs win initiative" do
      paused_loop = paused_loop_for(pipeline, "charge at the goblins")
      paused_loop.batch_update!(new_data: { "pipeline_outcome" => "Fig charges at one of the goblins, striking first." })
      goblin_1 = adventure.creature_sheets.create!(
        name: "Goblin", creature_type: "monster", origin: "template",
        strength: 8, dexterity: 13, constitution: 10, intelligence: 6,
        wisdom: 10, charisma: 8, level: 1, hp: 5, max_hp: 8
      )
      goblin_2 = adventure.creature_sheets.create!(
        name: "Goblin 2", creature_type: "monster", origin: "template",
        strength: 8, dexterity: 13, constitution: 10, intelligence: 6,
        wisdom: 10, charisma: 8, level: 1, hp: 4, max_hp: 4
      )

      npc_first_data = {
        "active" => true,
        "round" => 1,
        "current_turn" => "Goblin",
        "turn_order" => ["Goblin", "Player", "Goblin 2"],
        "participants" => [
          { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 8, "initiative" => 19, "conditions" => [], "creature_sheet_id" => goblin_1.id },
          { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 14, "conditions" => [] },
          { "name" => "Goblin 2", "type" => "npc", "hp" => 4, "max_hp" => 4, "initiative" => 9, "conditions" => [], "creature_sheet_id" => goblin_2.id }
        ],
        "terrain_notes" => nil
      }

      allow(DungeonMaster::Utilities::Warmaster).to receive(:compute_combat_initialization).and_return(npc_first_data)
      allow(pipeline).to receive(:request_npc_actions).and_return([
        ["npc_action_#{goblin_1.id}_0"],
        {
          "npc_action_#{goblin_1.id}_0" => {
            "parsed_response" => {
              "action" => "attack",
              "target" => "Player",
              "attack_modifier" => 0,
              "damage_dice" => "1d6"
            }
          }
        }
      ])
      allow(pipeline).to receive(:evaluator_fan_out_result!).and_wrap_original do |_orig, by_step, step_key, _phase|
        by_step.fetch(step_key)
      end
      allow(DungeonMaster::WorldTurn::NpcActionResolver).to receive(:resolve).and_return(
        lines: ["Goblin attacks Player: 15+0=15 vs AC 20 — miss."],
        player_hp_delta: 0,
        npc_muts: [],
        battlefield_patches: []
      )
      captured_rows = nil
      allow(pipeline).to receive(:run_accumulated_narrative_phase) do |rows|
        captured_rows = rows
        { action: :narrated, narrative: "stub" }
      end

      meta = {
        "intent" => {
          "intention" => "charge at the goblins",
          "expand_scene" => false,
          "affected_contexts" => ["combat"],
          "macro_significant" => false,
          "domain_results" => {}
        },
        "mutations" => {},
        "opener_outcome" => "Fig charges at one of the goblins, striking first.",
        "creature_data" => [
          { "name" => "Goblin", "creature_sheet_id" => goblin_1.id, "initiative" => 19 },
          { "name" => "Goblin 2", "creature_sheet_id" => goblin_2.id, "initiative" => 9 }
        ],
        "pending_opening_merged" => nil,
        "remaining_actions" => []
      }

      result = pipeline.run_initiative(14, meta)

      expect(result[:action]).to eq(:narrated)
      expect(DungeonMaster::WorldTurn::NpcActionResolver).to have_received(:resolve).once
      expect(paused_loop.reload.get("pipeline_outcome")).to eq("Goblin attacks Player: 15+0=15 vs AC 20 — miss.")
      combat_mutations = captured_rows.first.dig(:mutations, "combat_state_advancement")
      expect(combat_mutations["round"]).to eq(1)
      expect(combat_mutations["current_turn"]).to eq("Player")
    end
  end
end
