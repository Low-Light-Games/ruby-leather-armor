# frozen_string_literal: true

require "rails_helper"

RSpec.describe Currency do
  let(:full_purse) { { "gold" => 10, "silver" => 5, "copper" => 3, "platinum" => 2 } }

  describe ".zero" do
    it "returns a Currency with all zeroes" do
      expect(described_class.zero.total_coins).to eq(0)
      expect(described_class.zero.total_gp_value).to eq(0.0)
    end
  end

  describe "#initialize" do
    it "accepts a hash" do
      c = described_class.new(full_purse)
      expect(c.gold).to eq(10)
      expect(c.silver).to eq(5)
      expect(c.copper).to eq(3)
      expect(c.platinum).to eq(2)
    end

    it "treats missing keys as zero" do
      c = described_class.new("gold" => 7)
      expect(c.silver).to eq(0)
      expect(c.copper).to eq(0)
      expect(c.platinum).to eq(0)
    end

    it "accepts nil gracefully" do
      expect { described_class.new(nil) }.not_to raise_error
      expect(described_class.new(nil).total_coins).to eq(0)
    end
  end

  describe "#total_coins" do
    it "sums all denomination counts" do
      expect(described_class.new(full_purse).total_coins).to eq(20)
    end

    it "returns 0 for empty currency" do
      expect(described_class.zero.total_coins).to eq(0)
    end
  end

  describe "#total_gp_value" do
    it "converts each denomination at the correct rate" do
      c = described_class.new("gold" => 1, "silver" => 10, "copper" => 100, "platinum" => 1)
      # 1gp + 1gp (10sp) + 1gp (100cp) + 10gp (1pp) = 13.0
      expect(c.total_gp_value).to be_within(0.001).of(13.0)
    end

    it "handles partial denominations" do
      c = described_class.new("silver" => 1)
      expect(c.total_gp_value).to be_within(0.001).of(0.1)
    end
  end

  describe "#zero?" do
    it "returns true when all denominations are zero" do
      expect(described_class.zero).to be_zero
    end

    it "returns false when any denomination is nonzero" do
      expect(described_class.new("copper" => 1)).not_to be_zero
    end
  end

  describe "#add" do
    it "returns a new Currency summing both" do
      a = described_class.new("gold" => 3, "silver" => 2)
      b = described_class.new("gold" => 1, "copper" => 5)
      result = a.add(b)
      expect(result.gold).to eq(4)
      expect(result.silver).to eq(2)
      expect(result.copper).to eq(5)
    end

    it "does not mutate the original" do
      a = described_class.new("gold" => 3)
      a.add(described_class.new("gold" => 1))
      expect(a.gold).to eq(3)
    end
  end

  describe "#subtract" do
    it "returns a new Currency with the difference" do
      a = described_class.new("gold" => 10, "silver" => 3)
      b = described_class.new("gold" => 4, "silver" => 1)
      result = a.subtract(b)
      expect(result.gold).to eq(6)
      expect(result.silver).to eq(2)
    end
  end

  describe "#to_h" do
    it "returns a plain Hash with all four keys" do
      c = described_class.new("gold" => 5)
      h = c.to_h
      expect(h).to be_a(Hash)
      expect(h.keys).to match_array(%w[gold silver copper platinum])
      expect(h["gold"]).to eq(5)
    end
  end

  describe "#==" do
    it "is equal to another Currency with the same values" do
      a = described_class.new("gold" => 3)
      b = described_class.new("gold" => 3)
      expect(a).to eq(b)
    end

    it "is not equal to a Currency with different values" do
      expect(described_class.new("gold" => 1)).not_to eq(described_class.new("gold" => 2))
    end
  end
end
