# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::CreatureFactory, type: :service do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet)     { create(:adventure_sheet, adventure: adventure, level: 3) }

  let(:log)    { instance_double(DungeonMaster::Logging, log!: nil, ai_log!: nil) }
  let(:ai)     { instance_double(DungeonMaster::AiClient) }
  let(:config) { DmConfig.instance }

  subject(:factory) do
    described_class.new(adventure, sheet: sheet, log: log, ai: ai, config: config)
  end

  describe "#create_for_name" do
    context "when a creature with that name already exists" do
      before { create(:adventure_sheet, adventure: adventure, name: "Goblin") rescue nil }

      it "skips creation if creature_sheets already has the name" do
        adventure.creature_sheets.create!(
          name: "Goblin", creature_type: "monster", origin: "template",
          strength: 8, dexterity: 13, constitution: 10, intelligence: 6,
          wisdom: 10, charisma: 8, level: 1, hp: 5, max_hp: 5
        )

        expect { factory.create_for_name("Goblin") }.not_to(
          change { adventure.creature_sheets.count }
        )
      end
    end

    context "when no bestiary entry and fallback is template" do
      before { allow(config).to receive(:get).with("creature_creation_fallback").and_return("template") }

      it "creates a creature_sheet with origin: template" do
        expect { factory.create_for_name("Troll") }.to(
          change { adventure.creature_sheets.count }.by(1)
        )
        creature = adventure.creature_sheets.last
        expect(creature.origin).to eq("template")
        expect(creature.name).to eq("Troll")
      end

      it "scales stats to the party level" do
        # Level 3 party should map to tier 3 template
        creature = factory.create_for_name("Cave Bear")
        expect(creature.level).to eq(3)
        expect(creature.strength).to eq(DungeonMaster::CreatureFactory::CREATURE_TEMPLATE[3][:str])
      end
    end

    context "when no bestiary entry and fallback is disabled" do
      # nil defaults to "ai" via the `|| "ai"` guard; any other unknown value
      # hits the `else nil` branch and disables dynamic creation.
      before { allow(config).to receive(:get).with("creature_creation_fallback").and_return("disabled") }

      it "returns nil and logs a warning" do
        expect(log).to receive(:log!).with(:warn, /No bestiary match/)
        result = factory.create_for_name("Unknown Monster")
        expect(result).to be_nil
      end
    end
  end

  describe "CREATURE_TEMPLATE" do
    it "has entries for levels 1, 2, 3, 5, 8, 10" do
      expect(described_class::CREATURE_TEMPLATE.keys).to match_array([1, 2, 3, 5, 8, 10])
    end

    it "each entry has the required stat keys" do
      described_class::CREATURE_TEMPLATE.each do |level, stats|
        expect(stats).to include(:str, :dex, :con, :int, :wis, :cha, :ac, :bab, :hp, :speed),
          "tier #{level} is missing keys"
      end
    end
  end
end
