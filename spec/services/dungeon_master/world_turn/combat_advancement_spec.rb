# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::WorldTurn::CombatAdvancement, type: :service do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure, hp: 12, max_hp: 12) }

  describe ".build_after_world_turn" do
    it "normalizes inactive snapshots by dropping defeated npcs and combat-only fields" do
      original_ctx = {
        "active" => true,
        "round" => 4,
        "current_turn" => "Orc",
        "turn_order" => ["Orc", "Player"],
        "participants" => [
          { "name" => "Orc", "type" => "npc", "creature_sheet_id" => 11, "hp" => 0, "max_hp" => 8, "conditions" => [] },
          { "name" => "Player", "type" => "player", "hp" => 12, "max_hp" => 12, "conditions" => [] }
        ],
        "battlefield_ref" => { "id" => 81, "version" => 1, "topology" => "square" },
        "action_economy" => { "holder" => "Orc", "round" => 4 }
      }

      advancement = described_class.build_after_world_turn(
        { "active" => false, "round" => 4 },
        original_ctx,
        adventure: adventure,
        sheet: sheet
      )

      expect(advancement["active"]).to be(false)
      expect(advancement["participants"]).to eq([{ "name" => "Player", "type" => "player", "initiative" => 0, "hp" => 12, "max_hp" => 12, "conditions" => [], "position" => nil }])
      expect(advancement["turn_order"]).to eq([])
      expect(advancement["current_turn"]).to be_nil
      expect(advancement["battlefield_ref"]).to be_nil
      expect(advancement["action_economy"]).to be_nil
    end
  end
end
