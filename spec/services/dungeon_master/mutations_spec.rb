require "rails_helper"

RSpec.describe DungeonMaster::Mutations, type: :service do
  include_context "with mocked ai"

  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure, hp: 12, max_hp: 12) }
  let(:pipeline)  { build_pipeline(adventure) }

  describe "#apply_mutations — conditions" do
    it "adds a valid condition to the player sheet" do
      pipeline.send(:apply_mutations, {
        player: { conditions_add: ["fatigued"], conditions_remove: [] }
      })

      expect(sheet.reload.conditions).to eq(["fatigued"])
    end

    it "removes a condition from the player sheet" do
      sheet.update_column(:conditions, ["fatigued", "sickened"])

      pipeline.send(:apply_mutations, {
        player: { conditions_add: [], conditions_remove: ["fatigued"] }
      })

      expect(sheet.reload.conditions).to eq(["sickened"])
    end

    it "upgrades fatigued to exhausted via stacking" do
      sheet.update_column(:conditions, ["fatigued"])

      pipeline.send(:apply_mutations, {
        player: { conditions_add: ["fatigued"], conditions_remove: [] }
      })

      expect(sheet.reload.conditions).to eq(["exhausted"])
    end

    it "ignores invalid condition names" do
      pipeline.send(:apply_mutations, {
        player: { conditions_add: ["on_fire"], conditions_remove: [] }
      })

      expect(sheet.reload.conditions).to eq([])
    end

    it "returns true from apply_conditions when conditions change" do
      result = pipeline.send(:apply_conditions, sheet, ["fatigued"], [])
      expect(result).to be true
      expect(sheet.reload.conditions).to eq(["fatigued"])
    end

    it "returns false from apply_conditions when no conditions change" do
      result = pipeline.send(:apply_conditions, sheet, [], [])
      expect(result).to be false
    end

    it "triggers derived stat recomputation via apply_player_mutations" do
      sheet.recompute_derived_stats!

      pipeline.send(:apply_mutations, {
        player: { conditions_add: ["fatigued"], conditions_remove: [] }
      })

      sheet.reload
      expect(sheet.derived_stats["active_conditions"]).to eq(["fatigued"])
    end

    it "handles both add and remove in one call" do
      sheet.update_column(:conditions, ["shaken"])

      pipeline.send(:apply_mutations, {
        player: { conditions_add: ["fatigued"], conditions_remove: ["shaken"] }
      })

      expect(sheet.reload.conditions).to eq(["fatigued"])
    end
  end

  describe "#apply_mutations — NPC conditions" do
    let!(:creature) do
      adventure.creature_sheets.create!(
        name: "Goblin", creature_type: "monster", origin: "template",
        strength: 10, dexterity: 14, constitution: 12,
        intelligence: 8, wisdom: 10, charisma: 6,
        level: 1, hp: 6, max_hp: 6,
        derived_stats: { "ac" => 15 }
      )
    end

    it "adds conditions to NPC creature sheets" do
      pipeline.send(:apply_mutations, {
        npcs: [{ name: "Goblin", conditions_add: ["prone"], conditions_remove: [] }]
      })

      expect(creature.reload.conditions).to eq(["prone"])
    end

    it "removes conditions from NPC creature sheets" do
      creature.update_column(:conditions, ["prone", "shaken"])

      pipeline.send(:apply_mutations, {
        npcs: [{ name: "Goblin", conditions_add: [], conditions_remove: ["prone"] }]
      })

      expect(creature.reload.conditions).to eq(["shaken"])
    end
  end
end
