# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Utilities::CombatEndResolver, type: :service do
  describe ".check_player_status" do
    def sheet_stub(hp:, con: 10)
      instance_double("AdventureSheet", hp: hp, constitution: con)
    end

    it "returns :alive when hp > 0" do
      expect(described_class.check_player_status(sheet_stub(hp: 5))).to eq(:alive)
    end

    it "returns :disabled at exactly 0 hp" do
      expect(described_class.check_player_status(sheet_stub(hp: 0))).to eq(:disabled)
    end

    it "returns :dying when hp is negative but above -CON" do
      expect(described_class.check_player_status(sheet_stub(hp: -1, con: 12))).to eq(:dying)
    end

    it "returns :dead when hp reaches -CON" do
      expect(described_class.check_player_status(sheet_stub(hp: -10, con: 10))).to eq(:dead)
    end

    it "returns :dead when hp is below -CON" do
      expect(described_class.check_player_status(sheet_stub(hp: -15, con: 10))).to eq(:dead)
    end
  end

  describe ".check_combat_end" do
    # Stubs an adventure so CombatEndResolver gets the NPC records it needs without a factory.
    # Returns a plain Array from creature_sheets.where so Ruby's Array#all? handles the block correctly.
    def adventure_with_npcs(npc_rows, combat_participants)
      npc_doubles = npc_rows.map do |attrs|
        instance_double("CreatureSheet", hp: attrs[:hp], conditions: Array(attrs[:conditions]))
      end

      ctx = {
        "active" => true,
        "round" => 1,
        "current_turn" => "Player",
        "participants" => combat_participants
      }

      creature_sheets_assoc = instance_double("ActiveRecord::Associations::CollectionProxy")
      allow(creature_sheets_assoc).to receive(:where).and_return(npc_doubles)

      instance_double("Adventure", combat_context: ctx, creature_sheets: creature_sheets_assoc)
    end

    def sheet_stub(hp:, con: 10)
      instance_double("AdventureSheet", hp: hp, constitution: con)
    end

    context "when player is alive and NPCs are up" do
      it "reports combat active" do
        npc_participants = [{ "name" => "Wolf", "type" => "npc", "creature_sheet_id" => 1, "hp" => 8 }]
        adv = adventure_with_npcs([{ hp: 8, conditions: [] }], npc_participants)

        result = described_class.check_combat_end(adventure: adv, sheet: sheet_stub(hp: 10))
        expect(result[:combat][:combat_active]).to be true
        expect(result[:interaction][:player_death]).to be false
        expect(result[:interaction][:player_incapacitated]).to be false
      end
    end

    context "when player is dying (negative HP, above -CON)" do
      it "keeps combat active — bleed-out continues in the world turn" do
        npc_participants = [{ "name" => "Wolf", "type" => "npc", "creature_sheet_id" => 1, "hp" => 8 }]
        adv = adventure_with_npcs([{ hp: 8, conditions: [] }], npc_participants)

        result = described_class.check_combat_end(adventure: adv, sheet: sheet_stub(hp: -3, con: 10))
        expect(result[:combat][:combat_active]).to be true
        expect(result[:interaction][:player_incapacitated]).to be true
        expect(result[:interaction][:player_death]).to be false
      end
    end

    context "when player is dead (hp <= -CON)" do
      it "ends combat with player_death" do
        npc_participants = [{ "name" => "Wolf", "type" => "npc", "creature_sheet_id" => 1, "hp" => 8 }]
        adv = adventure_with_npcs([{ hp: 8, conditions: [] }], npc_participants)

        result = described_class.check_combat_end(adventure: adv, sheet: sheet_stub(hp: -10, con: 10))
        expect(result[:combat][:combat_active]).to be false
        expect(result[:combat][:combat_end_reason]).to eq(:player_death)
        expect(result[:interaction][:player_death]).to be true
      end
    end

    context "when all NPCs are eliminated (0 HP)" do
      it "ends combat regardless of player health" do
        npc_participants = [{ "name" => "Wolf", "type" => "npc", "creature_sheet_id" => 1, "hp" => 0 }]
        adv = adventure_with_npcs([{ hp: 0, conditions: [] }], npc_participants)

        result = described_class.check_combat_end(adventure: adv, sheet: sheet_stub(hp: 10))
        expect(result[:combat][:combat_active]).to be false
        expect(result[:combat][:combat_end_reason]).to eq(:all_npcs_defeated)
      end
    end

    context "when all NPCs have fled" do
      it "ends combat" do
        npc_participants = [{ "name" => "Wolf", "type" => "npc", "creature_sheet_id" => 1, "hp" => 5 }]
        adv = adventure_with_npcs([{ hp: 5, conditions: ["fled"] }], npc_participants)

        result = described_class.check_combat_end(adventure: adv, sheet: sheet_stub(hp: 10))
        expect(result[:combat][:combat_active]).to be false
        expect(result[:combat][:combat_end_reason]).to eq(:all_npcs_defeated)
      end
    end
  end
end
