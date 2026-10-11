require "rails_helper"

RSpec.describe Retrieval::ReciprocalRankFusion do
  it "scores each id by the sum of 1 / (k + rank) across rankings" do
    fused = described_class.fuse(%w[a b c], %w[c a], k: 60).to_h

    expect(fused["a"]).to be_within(1e-12).of((1.0 / 61) + (1.0 / 62))
    expect(fused["b"]).to be_within(1e-12).of(1.0 / 62)
    expect(fused["c"]).to be_within(1e-12).of((1.0 / 63) + (1.0 / 61))
  end

  it "ranks an id both retrievers agree on above one only a single retriever ranked first" do
    expect(described_class.fuse(%w[x shared], %w[y shared]).map(&:first).first).to eq("shared")
  end

  it "breaks score ties by first appearance and ignores duplicates within a ranking" do
    expect(described_class.fuse(%w[a a b], %w[b a]).map(&:first)).to eq(%w[a b])
    expect(described_class.fuse(%w[p], %w[q]).map(&:first)).to eq(%w[p q])
  end

  it "returns an empty list when every ranking is empty" do
    expect(described_class.fuse([], [])).to eq([])
  end
end
