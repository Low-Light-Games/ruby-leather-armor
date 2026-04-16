# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::WorldTurn::ParticipantLookup do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet, adventure: adventure, character_class: "fighter", level: 1).tap(&:recompute_derived_stats!)
  end

  let(:creature) do
    adventure.creature_sheets.create!(
      name: "Goblin Scout",
      creature_type: "monster",
      origin: "template",
      strength: 10, dexterity: 14, constitution: 10,
      intelligence: 8, wisdom: 10, charisma: 8,
      level: 1, hp: 6, max_hp: 6,
      derived_stats: { "ac" => 15, "bab" => 1, "speed" => 30 }
    ).tap(&:recompute_derived_stats!)
  end

  let(:combat_ctx) do
    {
      "participants" => [
        { "name" => "Goblin Scout", "creature_sheet_id" => creature.id }
      ]
    }
  end

  describe ".resolve_target_sheet!" do
    it "resolves player to the adventure sheet" do
      _k, s = described_class.resolve_target_sheet!(
        "player",
        combat_ctx: {},
        player_sheet: sheet,
        adventure: adventure
      )
      expect(s).to eq(sheet)
    end

    it "resolves a participant name case-insensitively" do
      _k, s = described_class.resolve_target_sheet!(
        "goblin scout",
        combat_ctx: combat_ctx,
        player_sheet: sheet,
        adventure: adventure
      )
      expect(s).to eq(creature)
    end

    it "raises when the name is not a participant" do
      expect do
        described_class.resolve_target_sheet!(
          "Dragon",
          combat_ctx: combat_ctx,
          player_sheet: sheet,
          adventure: adventure
        )
      end.to raise_error(DungeonMaster::CombatMechanicResolutionError, /not in combat participants/)
    end
  end

  describe ".defense_dc_for_target!" do
    it "returns touch AC when defense_kind is touch_ac" do
      dc = described_class.defense_dc_for_target!(
        "Goblin Scout",
        "touch_ac",
        combat_ctx: combat_ctx,
        player_sheet: sheet,
        adventure: adventure
      )
      expect(dc).to eq(creature.reload.derived_stats["touch_ac"].to_i)
    end
  end
end
