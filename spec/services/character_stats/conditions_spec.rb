require "rails_helper"

RSpec.describe CharacterStats::Conditions do
  describe "DEFINITIONS" do
    it "includes core PF1e conditions plus combat/narrative flags from DEFINITIONS" do
      expected = %w[
        fatigued exhausted shaken frightened panicked sickened nauseated
        entangled prone blinded staggered paralyzed stunned dazed poisoned grappled
        fled surrendered dead disabled petrified
      ]
      expect(described_class::VALID_CONDITIONS).to match_array(expected)
    end

    it "freezes the definitions hash" do
      expect(described_class::DEFINITIONS).to be_frozen
    end
  end

  describe ".valid?" do
    it "returns true for a known condition" do
      expect(described_class.valid?("fatigued")).to be true
    end

    it "returns false for an unknown condition" do
      expect(described_class.valid?("on_fire")).to be false
    end

    it "handles symbol input via to_s" do
      expect(described_class.valid?(:stunned)).to be true
    end
  end

  describe ".upgrade" do
    it "upgrades fatigued to exhausted when already fatigued" do
      result = described_class.upgrade(["fatigued"], "fatigued")
      expect(result).to eq(["exhausted"])
    end

    it "upgrades shaken to frightened when already shaken" do
      result = described_class.upgrade(["shaken"], "shaken")
      expect(result).to eq(["frightened"])
    end

    it "upgrades frightened to panicked when already frightened" do
      result = described_class.upgrade(["frightened"], "frightened")
      expect(result).to eq(["panicked"])
    end

    it "simply adds a condition when not already present" do
      result = described_class.upgrade([], "fatigued")
      expect(result).to eq(["fatigued"])
    end

    it "does not duplicate if condition already present and has no upgrade" do
      result = described_class.upgrade(["stunned"], "stunned")
      expect(result).to eq(["stunned"])
    end

    it "does not mutate the original array" do
      original = ["fatigued"]
      described_class.upgrade(original, "fatigued")
      expect(original).to eq(["fatigued"])
    end

    it "does not add the upgraded condition if already present" do
      result = described_class.upgrade(["fatigued", "exhausted"], "fatigued")
      expect(result).to eq(["exhausted"])
    end
  end

  describe ".ability_penalties" do
    it "returns combined penalties from multiple conditions" do
      penalties = described_class.ability_penalties(%w[fatigued entangled])
      expect(penalties["strength"]).to eq(-2)
      expect(penalties["dexterity"]).to eq(-6) # -2 fatigued + -4 entangled
    end

    it "returns empty hash for no conditions" do
      expect(described_class.ability_penalties([])).to eq({})
    end

    it "ignores unknown conditions" do
      expect(described_class.ability_penalties(["on_fire"])).to eq({})
    end
  end

  describe ".effective_scores" do
    it "returns forced scores from paralyzed" do
      overrides = described_class.effective_scores(["paralyzed"])
      expect(overrides).to eq({ "strength" => 0, "dexterity" => 0 })
    end

    it "returns empty hash when no conditions force scores" do
      expect(described_class.effective_scores(["fatigued"])).to eq({})
    end
  end

  describe ".speed_multiplier" do
    it "returns 0.5 for exhausted" do
      expect(described_class.speed_multiplier(["exhausted"])).to eq(0.5)
    end

    it "returns 1.0 for conditions without speed penalty" do
      expect(described_class.speed_multiplier(["fatigued"])).to eq(1.0)
    end

    it "returns the most restrictive multiplier" do
      expect(described_class.speed_multiplier(["exhausted", "fatigued"])).to eq(0.5)
    end

    it "returns 1.0 for empty conditions" do
      expect(described_class.speed_multiplier([])).to eq(1.0)
    end
  end

  describe ".restrictions" do
    it "returns deduplicated restrictions from multiple conditions" do
      restrictions = described_class.restrictions(%w[fatigued exhausted])
      expect(restrictions).to match_array(%w[cannot_run cannot_charge])
    end

    it "combines restrictions from different conditions" do
      restrictions = described_class.restrictions(%w[fatigued nauseated])
      expect(restrictions).to match_array(%w[cannot_run cannot_charge can_only_move])
    end

    it "returns empty array for no conditions" do
      expect(described_class.restrictions([])).to eq([])
    end
  end
end
