require "rails_helper"

RSpec.describe RetrievalEval::Stats do
  it "draws the same bootstrap CI for the same seed" do
    values = [1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0]

    expect(described_class.bootstrap_ci(values, resamples: 2_000, seed: 7))
      .to eq(described_class.bootstrap_ci(values, resamples: 2_000, seed: 7))
  end

  it "computes McNemar's exact p-value" do
    expect(described_class.mcnemar_exact(1, 9)).to eq(22.0 / 1024)
    expect(described_class.mcnemar_exact(0, 5)).to eq(0.0625)
    expect(described_class.mcnemar_exact(0, 0)).to eq(1.0)
  end

  it "applies Holm's adjustment in input order" do
    expect(described_class.holm([0.01, 0.04, 0.03])).to eq([0.03, 0.06, 0.06])
  end
end
