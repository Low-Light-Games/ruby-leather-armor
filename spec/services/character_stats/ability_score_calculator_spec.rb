# frozen_string_literal: true

require "rails_helper"

RSpec.describe CharacterStats::AbilityScoreCalculator, type: :model do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  let(:sheet) do
    create(:adventure_sheet,
      adventure: adventure,
      strength: 14, dexterity: 12, constitution: 13,
      intelligence: 10, wisdom: 11, charisma: 8,
      race: "human", character_class: "fighter", level: 3,
      racial_bonus_attribute: "strength")
  end

  subject(:result) { described_class.new(sheet).compute }

  it "returns a hash with the expected keys" do
    expect(result).to include(:race_info, :class_info, :final_scores, :mods,
                               :active_conditions, :bab, :good_saves)
  end

  describe "ability scores" do
    it "applies the racial flex bonus to the nominated ability" do
      # human flex +2 to strength: 14 base + 2 racial = 16
      expect(result[:final_scores]["strength"]).to eq(16)
    end

    it "leaves unmodified abilities unchanged" do
      expect(result[:final_scores]["intelligence"]).to eq(10)
    end
  end

  describe "ability modifiers" do
    it "computes mods as floor((score - 10) / 2)" do
      # STR 16 → mod 3, DEX 12 → mod 1, CON 13 → mod 1
      expect(result[:mods]["strength"]).to eq(3)
      expect(result[:mods]["dexterity"]).to eq(1)
      expect(result[:mods]["constitution"]).to eq(1)
    end
  end

  describe "BAB" do
    it "computes full BAB for fighter" do
      # fighter full BAB at level 3 = 3
      expect(result[:bab]).to eq(3)
    end
  end

  describe "good_saves" do
    it "lists fort for fighter" do
      expect(result[:good_saves]).to eq(["fort"])
    end
  end

  describe "race_info" do
    it "falls back to human when race is unknown" do
      sheet.race = "unknown_race"
      r = described_class.new(sheet).compute
      expect(r[:race_info][:size]).to eq("Medium")
    end
  end

  describe "conditions" do
    it "returns empty active_conditions when none are set" do
      expect(result[:active_conditions]).to eq([])
    end

    context "when sheet has the fatigued condition" do
      before { sheet.update_column(:conditions, ["fatigued"]) }

      it "reduces STR and DEX by 2" do
        clean = described_class.new(sheet.dup.tap { |s| s.conditions = [] }).compute
        fatigued = described_class.new(sheet).compute
        expect(fatigued[:final_scores]["strength"]).to eq(clean[:final_scores]["strength"] - 2)
        expect(fatigued[:final_scores]["dexterity"]).to eq(clean[:final_scores]["dexterity"] - 2)
      end

      it "reports fatigued in active_conditions" do
        expect(described_class.new(sheet).compute[:active_conditions]).to eq(["fatigued"])
      end
    end
  end
end
