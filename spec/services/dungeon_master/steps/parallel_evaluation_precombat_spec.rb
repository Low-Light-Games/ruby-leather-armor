# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::ParallelEvaluation#prepare_canonical_combatants", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story, traversal_context: { "nearby_npcs" => ["Two goblin scouts nearby"] }) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }
  let!(:goblin) do
    CreatureSheet.create!(
      adventure: adventure, name: "Goblin", creature_type: "monster", origin: "template",
      hp: 6, max_hp: 6, dexterity: 14, constitution: 10, strength: 10,
      intelligence: 8, wisdom: 10, charisma: 8
    )
  end
  let!(:goblin_2) do
    CreatureSheet.create!(
      adventure: adventure, name: "Goblin 2", creature_type: "monster", origin: "template",
      hp: 6, max_hp: 6, dexterity: 14, constitution: 10, strength: 10,
      intelligence: 8, wisdom: 10, charisma: 8
    )
  end

  it "returns the intent unchanged when warmaster cannot prepare any creatures" do
    intent = {
      intention: "I attack the goblins",
      domain_results: {
        "combat" => {
          transition: "combat_started",
          combatants: ["goblin"]
        }
      }
    }

    allow(adventure).to receive(:combat_active?).and_return(false)
    allow(DungeonMaster::Utilities::Warmaster).to receive(:prepare_from_names!)
      .and_return(status: :no_creatures, creature_data: [])

    result = pipeline.send(:prepare_canonical_combatants, intent)
    expect(result).to eq(intent)
  end

  it "passes beacon count to warmaster and persists a pending combat roster" do
    intent = {
      intention: "I attack the goblins",
      domain_results: {
        "combat" => {
          transition: "combat_started",
          combatants: ["goblin", "goblin"]
        }
      }
    }

    allow(adventure).to receive(:combat_active?).and_return(false)
    expect(DungeonMaster::Utilities::Warmaster).to receive(:prepare_from_names!).with(
      adventure: adventure,
      combatant_names: ["goblin", "goblin"],
      sheet: sheet,
      log: anything,
      config: anything,
      ai: anything
    ).and_return(
      status: :prepared,
      creature_data: [
        { name: "Goblin", creature_sheet_id: goblin.id, initiative: 15 },
        { name: "Goblin 2", creature_sheet_id: goblin_2.id, initiative: 11 }
      ]
    )

    result = pipeline.send(:prepare_canonical_combatants, intent)

    expect(result[:creature_data]).to match_array([
      hash_including(name: "Goblin", creature_sheet_id: goblin.id, initiative: 15),
      hash_including(name: "Goblin 2", creature_sheet_id: goblin_2.id, initiative: 11)
    ])

    pending = adventure.reload.combat_context
    expect(pending["active"]).to be(false)
    expect(pending["turn_order"]).to eq(["Goblin", "Goblin 2"])
    expect(pending["current_turn"]).to eq("Goblin")
    expect(pending["participants"].map { |p| p["name"] }).to eq(["Goblin", "Goblin 2"])
  end

  it "writes a warmaster play log for early pending-combat prep" do
    intent = {
      intention: "I attack the goblins",
      domain_results: {
        "combat" => {
          transition: "combat_started",
          combatants: ["goblin", "goblin"]
        }
      }
    }

    allow(adventure).to receive(:combat_active?).and_return(false)
    allow(DungeonMaster::Utilities::Warmaster).to receive(:prepare_from_names!).and_return(
      status: :prepared,
      creature_data: [
        { name: "Goblin", creature_sheet_id: goblin.id, initiative: 15 },
        { name: "Goblin 2", creature_sheet_id: goblin_2.id, initiative: 11 }
      ]
    )

    expect(pipeline.instance_variable_get(:@log)).to receive(:play_log!).with(
      "warmaster",
      /Pending combat roster prepared: 2 creature\(s\)/,
      parsed_response: hash_including(
        pending_combat: true,
        creature_count: 2,
        creatures: [
          hash_including(name: "Goblin", creature_sheet_id: goblin.id, initiative: 15),
          hash_including(name: "Goblin 2", creature_sheet_id: goblin_2.id, initiative: 11)
        ]
      )
    )

    pipeline.send(:prepare_canonical_combatants, intent)
  end
end
