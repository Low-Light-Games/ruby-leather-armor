require "rails_helper"

RSpec.describe RetrievalEval::RulesVariants do
  describe ".tie_break" do
    let(:vector) { [["a", 0.50], ["b", 0.495], ["c", 0.48], ["d", 0.479]] }

    it "re-orders only rules within epsilon of their run's head, by keyword rank" do
      expect(described_class.tie_break(vector, %w[d b], epsilon: 0.01)).to eq(%w[b a d c])
    end

    it "keeps vector order when nothing is close enough" do
      expect(described_class.tie_break(vector, %w[d b], epsilon: 0.001)).to eq(%w[a b c d])
    end
  end

  describe ".jargon?" do
    it "spots rule names and terms of art from the text alone" do
      expect(described_class.jargon?("I charge at the orc patrol")).to be(true)
      expect(described_class.jargon?("touch AC against the ray")).to be(true)
      expect(described_class.jargon?("I look around, what do I see?")).to be(false)
    end
  end
end
