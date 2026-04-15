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
        "needs_mechanics" => false,
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
          captured = kwargs[:accumulated_mutations]
          { action: :narrated, narrative: "stub" }
        end

        pipeline.run_initiative(15, meta)
        expect(captured).to eq([enriched_mutations])
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
        merged: { player_rolls: [{ type: "attack_roll", dc: 12 }], npc_actions: [], consequences: [], mechanical_summaries: ["attack"], bonus_context: { flank: false } },
        remaining_actions: []
      }

      meta = DungeonMaster::AdventurePlay::InitiativeRequestMetadata.for_awaiting_initiative(result)
      stored = meta["pending_opening_merged"] || meta[:pending_opening_merged]
      expect(stored).to include("player_rolls", "mechanical_summaries", "bonus_context")
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
  end
end
