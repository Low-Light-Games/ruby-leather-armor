# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Utilities::Combatant, type: :service do
  describe ".from_context_hash / #to_context_hash" do
    it "round-trips participant fields" do
      h = {
        "name" => "Wolf 1",
        "type" => "npc",
        "creature_sheet_id" => 42,
        "initiative" => 14,
        "hp" => 8,
        "max_hp" => 13,
        "conditions" => ["prone"],
        "position" => "10 ft"
      }
      c = described_class.from_context_hash(h)
      expect(c.to_context_hash).to include(
        "name" => "Wolf 1",
        "type" => "npc",
        "creature_sheet_id" => 42,
        "initiative" => 14,
        "hp" => 8,
        "max_hp" => 13,
        "conditions" => ["prone"],
        "position" => "10 ft"
      )
    end

    it "defaults max_hp from hp when max_hp missing" do
      c = described_class.from_context_hash("name" => "X", "type" => "npc", "initiative" => 1, "hp" => 5)
      expect(c.max_hp).to eq(5)
    end
  end

  describe "#defeated?" do
    it "is true at 0 hp or dead condition" do
      expect(described_class.new(name: "A", creature_sheet_id: 1, type: "npc", initiative: 1, hp: 0, max_hp: 5).defeated?).to be true
      expect(described_class.new(name: "B", creature_sheet_id: 1, type: "npc", initiative: 1, hp: 3, max_hp: 5, conditions: ["dead"]).defeated?).to be true
    end

    it "is true for NPCs at negative hp (no PF1e dying mechanic for NPCs)" do
      expect(described_class.new(name: "A", creature_sheet_id: 1, type: "npc", initiative: 1, hp: -3, max_hp: 5).defeated?).to be true
    end
  end

  describe "#dying?" do
    it "is true when hp is negative and not dead" do
      expect(described_class.new(name: "A", creature_sheet_id: 1, type: "player", initiative: 5, hp: -3, max_hp: 10).dying?).to be true
    end

    it "is false when hp is 0" do
      expect(described_class.new(name: "A", creature_sheet_id: 1, type: "player", initiative: 5, hp: 0, max_hp: 10).dying?).to be false
    end

    it "is false when hp is positive" do
      expect(described_class.new(name: "A", creature_sheet_id: 1, type: "player", initiative: 5, hp: 5, max_hp: 10).dying?).to be false
    end

    it "is false when dead condition is set" do
      expect(described_class.new(name: "A", creature_sheet_id: 1, type: "player", initiative: 5, hp: -10, max_hp: 10, conditions: ["dead"]).dying?).to be false
    end
  end

  describe "#eliminated_from_encounter?" do
    it "is true for NPCs when dead, defeated (0 HP), fled, or surrendered" do
      base = { name: "A", creature_sheet_id: 1, type: "npc", initiative: 1, hp: 5, max_hp: 5 }
      expect(described_class.new(**base, conditions: ["dead"]).eliminated_from_encounter?).to be true
      expect(described_class.new(**base, conditions: ["fled"]).eliminated_from_encounter?).to be true
      expect(described_class.new(**base, conditions: ["surrendered"]).eliminated_from_encounter?).to be true
      expect(described_class.new(**base, hp: 0).eliminated_from_encounter?).to be true
    end

    it "is false when NPC is only paralyzed (still in the encounter)" do
      base = { name: "A", creature_sheet_id: 1, type: "npc", initiative: 1, hp: 5, max_hp: 5 }
      expect(described_class.new(**base, conditions: ["paralyzed"]).eliminated_from_encounter?).to be false
    end

    it "is false for a dying player (negative HP without dead condition)" do
      player = { name: "Player", creature_sheet_id: nil, type: "player", initiative: 10, hp: -3, max_hp: 10 }
      expect(described_class.new(**player).eliminated_from_encounter?).to be false
    end
  end

  describe "#can_act?" do
    it "is false when hp <= 0 (defeated or dying)" do
      base = { name: "A", creature_sheet_id: 1, type: "player", initiative: 5, max_hp: 10 }
      expect(described_class.new(**base, hp: 0).can_act?).to be false
      expect(described_class.new(**base, hp: -3).can_act?).to be false
    end

    it "is false when fled, surrendered, paralyzed, or petrified" do
      base = { name: "A", creature_sheet_id: 1, type: "npc", initiative: 1, hp: 5, max_hp: 5 }
      expect(described_class.new(**base, conditions: ["fled"]).can_act?).to be false
      expect(described_class.new(**base, conditions: ["surrendered"]).can_act?).to be false
      expect(described_class.new(**base, conditions: ["paralyzed"]).can_act?).to be false
      expect(described_class.new(**base, conditions: ["petrified"]).can_act?).to be false
    end
  end
end
