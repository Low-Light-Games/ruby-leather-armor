require "rails_helper"

RSpec.describe RetrievalEval::Stats do
  describe ".bootstrap_ci" do
    let(:values) { [1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0] }

    it "is deterministic for a given seed" do
      first = described_class.bootstrap_ci(values, resamples: 2_000, seed: 7)

      expect(described_class.bootstrap_ci(values, resamples: 2_000, seed: 7)).to eq(first)
      expect(first).to eq([0.4, 1.0])
    end

    it "brackets the sample mean" do
      low, high = described_class.bootstrap_ci(values, resamples: 2_000, seed: 7)

      expect(low).to be <= described_class.mean(values)
      expect(high).to be >= described_class.mean(values)
    end

    it "collapses to the value when every sample is the same" do
      expect(described_class.bootstrap_ci([0.5] * 8, resamples: 500, seed: 1)).to eq([0.5, 0.5])
    end
  end

  describe ".paired_difference_ci" do
    it "resamples pairs with the same indices as bootstrap_ci" do
      a = [1.0, 0.0, 1.0, 0.5, 1.0, 0.0]

      expect(described_class.paired_difference_ci(a, [0.0] * 6, resamples: 1_000, seed: 3))
        .to eq(described_class.bootstrap_ci(a, resamples: 1_000, seed: 3))
    end

    it "rejects samples of different lengths" do
      expect { described_class.paired_difference_ci([1.0], [1.0, 0.0]) }.to raise_error(ArgumentError)
    end
  end

  describe ".mcnemar_exact" do
    it "matches the exact binomial p-value for a known table" do
      # b = 1, c = 9: p = 2 * (C(10,0) + C(10,1)) / 2^10 = 22 / 1024
      expect(described_class.mcnemar_exact(1, 9)).to eq(22.0 / 1024)
      expect(described_class.mcnemar_exact(9, 1)).to eq(22.0 / 1024)
      # b = 0, c = 5: p = 2 / 32
      expect(described_class.mcnemar_exact(0, 5)).to eq(0.0625)
    end

    it "caps the p-value at 1 and handles no discordant pairs" do
      expect(described_class.mcnemar_exact(5, 5)).to eq(1.0)
      expect(described_class.mcnemar_exact(0, 0)).to eq(1.0)
    end
  end

  it "counts discordant pairs" do
    expect(described_class.discordant([1, 1, 0, 0, 1], [1, 0, 1, 0, 0])).to eq([2, 1])
  end

  it "applies Holm's step-down adjustment in input order" do
    expect(described_class.holm([0.01, 0.04, 0.03])).to eq([0.03, 0.06, 0.06])
  end

  it "interpolates percentiles between ranks" do
    expect(described_class.percentile([1.0, 2.0, 3.0, 4.0], 0.5)).to eq(2.5)
  end
end
