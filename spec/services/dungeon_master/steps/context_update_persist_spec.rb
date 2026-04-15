# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::ContextUpdate#persist_micro_contexts", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "reads traversal_context from parsed JSON (not bare traversal)" do
    adventure.update!(traversal_context: { "floor" => 1 })
    parsed = { "traversal_context" => { "floor" => 2 } }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    expect(adventure.traversal_context).to include("floor" => 2)
  end

  it "reads combat_context and deep-merges with existing combat" do
    adventure.update!(combat_context: { "active" => true, "round" => 1 })
    parsed = { "combat_context" => { "round" => 2 } }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    expect(adventure.combat_context["active"]).to be true
    expect(adventure.combat_context["round"]).to eq(2)
  end

  it "ignores synthetic combat activation without combat_initialization" do
    adventure.update!(combat_context: {})
    parsed = { "combat_context" => { "active" => true, "round" => 1, "turn_order" => ["Player", "Goblin"] } }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    expect(adventure.combat_context).to eq({})
  end

  it "allows combat activation when combat_initialization is present" do
    adventure.update!(combat_context: { "active" => false, "legacy_key" => "old" })
    parsed = { "combat_context" => { "active" => true, "round" => 1, "turn_order" => ["Player", "Goblin"] } }
    mutations = { "combat_initialization" => parsed["combat_context"] }

    pipeline.send(:persist_micro_contexts, parsed, mutations)
    adventure.reload

    expect(adventure.combat_context["active"]).to be true
    expect(adventure.combat_context["turn_order"]).to eq(["Player", "Goblin"])
    expect(adventure.combat_context).not_to have_key("legacy_key")
  end

  it "repairs dropped npc creature_sheet_id from existing active combat participants" do
    goblin = CreatureSheet.create!(
      adventure: adventure, name: "Goblin", creature_type: "monster", origin: "template",
      hp: 5, max_hp: 8, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8
    )
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [
          { "name" => "Goblin", "type" => "npc", "creature_sheet_id" => goblin.id, "hp" => 5, "max_hp" => 8, "conditions" => [] },
          { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "conditions" => [] }
        ]
      }
    )

    parsed = {
      "combat_context" => {
        "unchanged" => false,
        "context" => {
          "participants" => [
            { "name" => "Goblin", "type" => "npc", "hp" => 4, "max_hp" => 8, "conditions" => [] },
            { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "conditions" => [] }
          ]
        }
      }
    }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    goblin_row = adventure.combat_context.fetch("participants").find { |p| p["name"] == "Goblin" }
    expect(goblin_row["creature_sheet_id"]).to eq(goblin.id)
    expect(goblin_row["hp"]).to eq(4)
  end

  it "rejects active-combat participant identity loss when it cannot be repaired" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [
          { "name" => "Goblin", "type" => "npc", "creature_sheet_id" => 999, "hp" => 5, "max_hp" => 8, "conditions" => [] }
        ]
      }
    )

    parsed = {
      "combat_context" => {
        "unchanged" => false,
        "context" => {
          "participants" => [
            { "name" => "Unknown Goblin", "type" => "npc", "hp" => 5, "max_hp" => 8, "conditions" => [] }
          ]
        }
      }
    }

    expect {
      pipeline.send(:persist_micro_contexts, parsed)
    }.to raise_error(DungeonMaster::AiError, /dropped creature_sheet_id/i)
  end

  it "wraps per-domain fan-out back into the legacy aggregate micro result shape" do
    by_step = {
      "traversal_context_update" => { "parsed_response" => { "unchanged" => false, "context" => { "floor" => 2 } } },
      "combat_context_update" => { "parsed_response" => { "unchanged" => true, "context" => { "active" => true } } },
      "social_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "exploration_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "rest_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "inventory_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "meta_context_update" => { "parsed_response" => { "scene_summary" => "At the doorway.", "new_creatures" => [], "context_wishes" => [] } }
    }

    parsed = pipeline.send(:aggregate_micro_context_results, by_step)

    expect(parsed["traversal_context"]).to eq({ "unchanged" => false, "context" => { "floor" => 2 } })
    expect(parsed["scene_summary"]).to eq("At the doorway.")
  end

  it "routes run_micro_context_update through the per-domain fan-out path" do
    by_step = {
      "traversal_context_update" => { "parsed_response" => { "unchanged" => false, "context" => { "current_location" => "Hallway" } } },
      "combat_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "social_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "exploration_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "rest_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "inventory_context_update" => { "parsed_response" => { "unchanged" => true, "context" => {} } },
      "meta_context_update" => { "parsed_response" => { "scene_summary" => "In the hallway.", "new_creatures" => [], "context_wishes" => [] } }
    }
    allow(pipeline).to receive(:run_micro_context_updates_fan_out).and_return(by_step)

    parsed = pipeline.send(:run_micro_context_update, "The hero steps into the hallway.", nil)

    expect(parsed["traversal_context"]).to eq({ "unchanged" => false, "context" => { "current_location" => "Hallway" } })
    expect(parsed["scene_summary"]).to eq("In the hallway.")
  end
end
