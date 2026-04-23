require "rails_helper"

RSpec.describe StripePlans do
  describe ".token_limit_for" do
    it "returns integer limits from config/stripe_plans.yml" do
      expect(described_class.token_limit_for("free")).to be_a(Integer)
      expect(described_class.token_limit_for("adventurer")).to be > described_class.token_limit_for("free")
    end
  end

  describe ".find_by_price_id" do
    it "returns the matching plan" do
      plan = described_class.find_by_price_id("price_1TPOxkCkABKwIzb7T0v0x6DM")
      expect(plan&.key).to eq("scout")
    end

    it "returns nil for unknown price ids" do
      expect(described_class.find_by_price_id("price_missing")).to be_nil
    end
  end
end
