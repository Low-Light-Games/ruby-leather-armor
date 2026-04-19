# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Rolls::CombatDice, type: :service do
  describe ".d20_attack_vs_ac" do
    it "hits when total meets AC" do
      allow(described_class).to receive(:roll_d20).and_return(15)
      r = described_class.d20_attack_vs_ac(modifier: 5, ac: 18)
      expect(r[:d20]).to eq(15)
      expect(r[:total]).to eq(20)
      expect(r[:hit]).to be true
    end

    it "misses when total is below AC" do
      allow(described_class).to receive(:roll_d20).and_return(10)
      r = described_class.d20_attack_vs_ac(modifier: 2, ac: 15)
      expect(r[:hit]).to be false
    end
  end

  describe ".roll_damage_expression" do
    it "parses NdM+K (1d1+0 is always 1)" do
      expect(described_class.roll_damage_expression("1d1+0")).to eq(1)
    end

    it "falls back for garbage input" do
      v = described_class.roll_damage_expression("not dice")
      expect(v).to be_between(1, 4)
    end
  end
end
