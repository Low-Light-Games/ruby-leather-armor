# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::PipelineEngine — prepared hostile opener flow", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 14, wisdom: 10, charisma: 10,
      race: "human", character_class: "wizard", level: 1)
  end
  let(:pipeline) { build_pipeline(adventure) }

  let!(:goblin) do
    CreatureSheet.create!(
      adventure: adventure, name: "Goblin", creature_type: "monster", origin: "template",
      hp: 5, max_hp: 5, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8
    )
  end

  let(:prepared_intent) do
    {
      intention: "cast Ray of Frost on one of the goblins",
      expand_scene: false,
      affected_contexts: ["combat"],
      macro_significant: false,
      domain_results: {},
      creature_data: [{ name: "Goblin", creature_sheet_id: goblin.id, initiative: 10 }]
    }
  end

  it "awaits the opener roll before initiative when prepared creature_data is present" do
    merged = {
      player_rolls: [{ type: "attack_roll", dc: 16, description: "Ray of Frost vs goblin" }],
      npc_actions: [],
      consequences: [],
      mechanical_summaries: ["Ray of Frost requires an attack roll."]
    }

    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(true)
    allow(pipeline).to receive(:run_capability_check).and_return({ allowed: true, reason: nil })
    allow(pipeline).to receive(:merge_mechanical_evaluations_and_prepare_rolls).and_return(merged)

    result = pipeline.send(:resolve_with_mechanics, prepared_intent, [])
    expect(result[:status]).to eq(:awaiting_rolls)
    expect(result[:intent][:creature_data]).to be_present
  end

  it "prompts for initiative after the opener resolves if a prepared hostile remains alive" do
    allow(pipeline).to receive(:resolve_npc_actions).and_return("")
    allow(pipeline).to receive(:run_mechanic).and_return(
      outcome: "Meein M'ecks casts Ray of Frost but misses the goblin.",
      mutations: {
        "player" => { "hp_change" => 0, "conditions_add" => [], "conditions_remove" => [], "buffs_add" => [], "buffs_remove" => [] },
        "npcs" => [{ "name" => "Goblin", "creature_sheet_id" => goblin.id, "hp_change" => 0, "conditions_add" => [], "conditions_remove" => [] }],
        "inventory" => {},
        "items_consumed" => [],
        "spells_used" => ["Ray of Frost"]
      }
    )
    allow(pipeline).to receive(:run_time_keeper).and_return({ encounter: false })

    result = pipeline.send(:finish_resolution,
      prepared_intent,
      { player_rolls: [{ type: "attack_roll", dc: 16 }], npc_actions: [], consequences: [], mechanical_summaries: ["attack"] },
      "Rolled 3 for: Ray of Frost")

    expect(result[:status]).to eq(:awaiting_initiative)
    expect(result[:creature_data]).to eq(prepared_intent[:creature_data])
  end

  it "does not prompt for initiative after the opener if no prepared hostile remains alive" do
    goblin.update!(hp: 0, conditions: ["dead"])
    allow(pipeline).to receive(:resolve_npc_actions).and_return("")
    allow(pipeline).to receive(:run_mechanic).and_return(
      outcome: "Meein M'ecks drops the goblin with Ray of Frost.",
      mutations: {
        "player" => { "hp_change" => 0, "conditions_add" => [], "conditions_remove" => [], "buffs_add" => [], "buffs_remove" => [] },
        "npcs" => [{ "name" => "Goblin", "creature_sheet_id" => goblin.id, "hp_change" => -5, "conditions_add" => ["dead"], "conditions_remove" => [] }],
        "inventory" => {},
        "items_consumed" => [],
        "spells_used" => ["Ray of Frost"]
      }
    )
    allow(pipeline).to receive(:run_time_keeper).and_return({ encounter: false })

    result = pipeline.send(:finish_resolution,
      prepared_intent,
      { player_rolls: [{ type: "attack_roll", dc: 16 }], npc_actions: [], consequences: [], mechanical_summaries: ["attack"] },
      "Rolled 18 for: Ray of Frost")

    expect(result[:status]).to eq(:resolved)
  end

  it "does not debit round-1 action economy when initiative is finalized after the opener" do
    paused_loop = AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: pipeline.instance_variable_get(:@log).registry_entry_uuid,
      sequence_index: 0,
      raw_action: "cast Ray of Frost on one of the goblins",
      player_intent: "cast Ray of Frost on one of the goblins",
      status: "paused"
    )
    pipeline.bind_current_loop!(paused_loop)

    meta = {
      "intent" => prepared_intent.deep_stringify_keys,
      "mutations" => {},
      "creature_data" => prepared_intent[:creature_data].map(&:deep_stringify_keys),
      "pending_opening_merged" => nil,
      "remaining_actions" => []
    }

    result = pipeline.run_initiative(23, meta)
    adventure.reload

    expect(result[:action]).to eq(:combat_initialized)
    expect(result[:combat_start_message]).to include("It's your turn")
    expect(adventure.combat_context.dig("action_economy", "standard_available")).to eq(true)
    expect(adventure.combat_context.dig("action_economy", "move_available")).to eq(true)
  end

  it "upgrades the pending roster into active combat instead of rebuilding from creature_data" do
    paused_loop = AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: pipeline.instance_variable_get(:@log).registry_entry_uuid,
      sequence_index: 0,
      raw_action: "cast Ray of Frost on one of the goblins",
      player_intent: "cast Ray of Frost on one of the goblins",
      status: "paused"
    )
    pipeline.bind_current_loop!(paused_loop)

    adventure.update!(combat_context: {
      "active" => false,
      "round" => 1,
      "current_turn" => "Goblin",
      "turn_order" => ["Goblin"],
      "participants" => [
        {
          "name" => "Goblin",
          "type" => "npc",
          "initiative" => 10,
          "hp" => 5,
          "max_hp" => 5,
          "conditions" => [],
          "creature_sheet_id" => goblin.id
        }
      ],
      "terrain_notes" => nil
    })
    goblin.update!(hp: 3)

    meta = {
      "intent" => prepared_intent.deep_stringify_keys,
      "mutations" => {},
      "creature_data" => [{ "name" => "Wrong Goblin", "creature_sheet_id" => -1, "initiative" => 1 }],
      "pending_opening_merged" => nil,
      "remaining_actions" => []
    }

    result = pipeline.run_initiative(23, meta)
    adventure.reload

    expect(result[:action]).to eq(:combat_initialized)
    goblin_row = adventure.combat_context["participants"].find { |p| p["type"] == "npc" }
    expect(goblin_row["name"]).to eq("Goblin")
    expect(goblin_row["creature_sheet_id"]).to eq(goblin.id)
    expect(goblin_row["hp"]).to eq(3)
    expect(adventure.combat_context["active"]).to be(true)
    expect(adventure.combat_context["battlefield_ref"]).to be_present
    expect(adventure.combat_context["action_economy"]).to be_present
  end

  it "ignores ended combat snapshots with a player row when finalizing fresh initiative" do
    paused_loop = AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: pipeline.instance_variable_get(:@log).registry_entry_uuid,
      sequence_index: 0,
      raw_action: "cast Ray of Frost on one of the goblins",
      player_intent: "cast Ray of Frost on one of the goblins",
      status: "paused"
    )
    pipeline.bind_current_loop!(paused_loop)

    adventure.update!(combat_context: {
      "active" => false,
      "round" => 2,
      "current_turn" => "Player",
      "turn_order" => ["Player", "Orc"],
      "participants" => [
        {
          "name" => "Player",
          "type" => "player",
          "initiative" => 16,
          "hp" => 10,
          "max_hp" => 10,
          "conditions" => []
        },
        {
          "name" => "Orc",
          "type" => "npc",
          "initiative" => 9,
          "hp" => 0,
          "max_hp" => 8,
          "conditions" => ["dead"]
        }
      ],
      "terrain_notes" => nil
    })

    meta = {
      "intent" => prepared_intent.deep_stringify_keys,
      "mutations" => {},
      "creature_data" => prepared_intent[:creature_data].map(&:deep_stringify_keys),
      "pending_opening_merged" => nil,
      "remaining_actions" => []
    }

    result = pipeline.run_initiative(23, meta)
    adventure.reload

    expect(result[:action]).to eq(:combat_initialized)
    npc_rows = adventure.combat_context["participants"].select { |row| row["type"] == "npc" }
    expect(npc_rows.map { |row| row["name"] }).to contain_exactly("Goblin")
    expect(npc_rows.first["creature_sheet_id"]).to eq(goblin.id)
  end
end
