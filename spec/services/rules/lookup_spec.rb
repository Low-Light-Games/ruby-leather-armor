require "rails_helper"

RSpec.describe Rules::Lookup do
  let(:ai) { double("ai") }
  let(:log) { double("log", embedding_cache: nil) }

  def basis(*weights)
    Array.new(1536, 0.0).tap { |v| weights.each_with_index { |w, i| v[i] = w } }
  end

  def rule!(slug, name, body, vector)
    RuleEmbedding.create!(slug: slug, domain: "combat", name: name, brief: nil, body: body,
                          text_digest: slug, embedding: vector)
  end

  def lookup(limit: 2)
    described_class.call(ai: ai, log: log, query_text: "I aim at its touch AC", limit: limit)
  end

  before do
    rule!("climb", "Climb", "Climb walls and ropes.", basis(0.0, 1.0))
    rule!("grapple", "Grapple", "Wrestle a foe to the ground.", basis(1.0))
    rule!("armor_class", "Armor Class", "Touch AC excludes armor, shield, and natural armor.", basis(0.0, 0.0, 1.0))

    # Nearest by cosine: climb, then grapple, then armor_class.
    allow(ai).to receive(:embeddings).and_return([basis(0.1, 0.9)])
    allow(log).to receive(:timed_embedding_call) { |*_args, **_kwargs, &block| block.call }
    allow(log).to receive(:play_log!)
    allow(log).to receive(:report_error)
  end

  context "when hybrid_rules_retrieval is off" do
    it "returns the vector neighbours only" do
      expect(lookup.pluck(:slug)).to eq(%w[climb grapple])
    end

    it "returns nothing when embedding the query fails" do
      allow(ai).to receive(:embeddings).and_raise(Ai::Error, "openai down")

      expect(lookup).to eq([])
      expect(log).to have_received(:report_error)
    end
  end

  context "when hybrid_rules_retrieval is on" do
    before { create(:feature_flag, :on, key: "hybrid_rules_retrieval") }

    it "fuses the keyword match into the vector ranking" do
      hits = lookup

      # armor_class is 3rd by vector but the only keyword match ("touch", "AC"),
      # so RRF lifts it above the vector winner.
      expect(hits.pluck(:slug)).to eq(%w[armor_class climb])
      expect(hits.first[:rrf_score]).to be > hits.second[:rrf_score]
      expect(hits.second[:distance]).to be_within(1e-6).of(1 - (0.9 / Math.sqrt(0.82)))
    end

    it "falls back to the keyword ranking when embedding the query fails" do
      allow(ai).to receive(:embeddings).and_raise(Ai::Error, "openai down")

      hits = lookup

      expect(hits.pluck(:slug)).to eq(%w[armor_class])
      expect(hits.first[:distance]).to be_nil
      expect(log).not_to have_received(:report_error)
    end

    it "records the retrieval mode in the play log" do
      lookup

      expect(log).to have_received(:play_log!).with(
        "rules_retrieved", anything, parsed_response: hash_including(retrieval: "hybrid")
      )
    end
  end
end
