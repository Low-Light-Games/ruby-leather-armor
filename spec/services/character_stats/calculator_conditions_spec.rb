require "rails_helper"

RSpec.describe CharacterStats::Calculator, "condition integration", type: :model do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  let(:sheet) do
    create(:adventure_sheet,
      adventure: adventure,
      strength: 14, dexterity: 16, constitution: 13,
      intelligence: 10, wisdom: 11, charisma: 8,
      race: "human", character_class: "fighter", level: 1,
      racial_bonus_attribute: "strength")
  end

  subject(:stats) { described_class.new(sheet).compute }

  context "with no conditions" do
    it "includes empty active_conditions" do
      expect(stats[:active_conditions]).to eq([])
    end

    it "includes empty condition_restrictions" do
      expect(stats[:condition_restrictions]).to eq([])
    end

    it "produces ac_breakdown with Base entry" do
      expect(stats[:ac_breakdown]).to be_an(Array)
      expect(stats[:ac_breakdown].first).to include(label: "Base", value: 10)
    end

    it "produces save breakdowns as arrays" do
      expect(stats[:fort_breakdown]).to be_an(Array)
      expect(stats[:ref_breakdown]).to be_an(Array)
      expect(stats[:will_breakdown]).to be_an(Array)
    end
  end

  context "when fatigued" do
    before { sheet.update_column(:conditions, ["fatigued"]) }

    it "reduces STR and DEX by 2" do
      clean = described_class.new(sheet.dup.tap { |s| s.conditions = [] }).compute
      expect(stats[:final_scores]["strength"]).to eq(clean[:final_scores]["strength"] - 2)
      expect(stats[:final_scores]["dexterity"]).to eq(clean[:final_scores]["dexterity"] - 2)
    end

    it "lists cannot_run and cannot_charge restrictions" do
      expect(stats[:condition_restrictions]).to match_array(%w[cannot_run cannot_charge])
    end

    it "reports fatigued in active_conditions" do
      expect(stats[:active_conditions]).to eq(["fatigued"])
    end

    it "does not change speed (no speed_multiplier on fatigued)" do
      clean = described_class.new(sheet.dup.tap { |s| s.conditions = [] }).compute
      expect(stats[:speed]).to eq(clean[:speed])
    end
  end

  context "when exhausted" do
    before { sheet.update_column(:conditions, ["exhausted"]) }

    it "reduces STR and DEX by 6" do
      clean = described_class.new(sheet.dup.tap { |s| s.conditions = [] }).compute
      expect(stats[:final_scores]["strength"]).to eq(clean[:final_scores]["strength"] - 6)
      expect(stats[:final_scores]["dexterity"]).to eq(clean[:final_scores]["dexterity"] - 6)
    end

    it "halves movement speed" do
      clean = described_class.new(sheet.dup.tap { |s| s.conditions = [] }).compute
      expect(stats[:speed]).to eq((clean[:speed] * 0.5).floor)
    end
  end

  context "when paralyzed" do
    before { sheet.update_column(:conditions, ["paralyzed"]) }

    it "sets STR and DEX to 0" do
      expect(stats[:final_scores]["strength"]).to eq(0)
      expect(stats[:final_scores]["dexterity"]).to eq(0)
    end

    it "includes cannot_act restriction" do
      expect(stats[:condition_restrictions]).to include("cannot_act")
    end
  end

  context "when stunned" do
    before { sheet.update_column(:conditions, ["stunned"]) }

    it "applies AC modifier from stunned" do
      clean = described_class.new(sheet.dup.tap { |s| s.conditions = [] }).compute
      expect(stats[:ac]).to be < clean[:ac]
    end

    it "includes stunned in ac_breakdown" do
      condition_entries = stats[:ac_breakdown].select { |e| e[:type] == "condition" }
      expect(condition_entries).not_to be_empty
      expect(condition_entries.first[:label]).to eq("Stunned")
    end
  end

  describe "breakdown filtering" do
    it "omits zero-value entries except Base" do
      stats[:ac_breakdown].each do |entry|
        next if entry[:label] == "Base"

        expect(entry[:value].to_i).not_to eq(0)
      end
    end
  end
end
