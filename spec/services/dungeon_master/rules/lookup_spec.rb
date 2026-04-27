require "rails_helper"

RSpec.describe DungeonMaster::Rules::Lookup do
  let(:ai)  { instance_double(DungeonMaster::AiClient) }
  let(:log) do
    log_double = double("Logging")
    allow(log_double).to receive(:timed_embedding_call) { |*_args, **_kw, &block| block.call }
    allow(log_double).to receive(:play_log!)
    allow(log_double).to receive(:report_error)
    log_double
  end

  before do
    DungeonMaster::Rules.clear_cache!
    RuleEmbedding.delete_all
  end

  it "returns the closest rule entries by cosine similarity" do
    fixed = Array.new(1536, 0.0).tap { |arr| arr[0] = 1.0 }
    other = Array.new(1536, 0.0).tap { |arr| arr[1] = 1.0 }

    RuleEmbedding.create!(slug: "climbing", domain: "exploration", name: "Climbing",
                          brief: "Move on a vertical surface.",
                          body:  "Climb DC depends on slope and grip.",
                          text_digest: "a", embedding: fixed)
    RuleEmbedding.create!(slug: "diplomacy", domain: "social", name: "Diplomacy",
                          brief: "Persuade an NPC.",
                          body:  "Diplomacy DC scales with attitude.",
                          text_digest: "b", embedding: other)

    allow(ai).to receive(:embeddings).and_return([fixed])

    hits = described_class.call(ai: ai, log: log, query_text: "I climb the wall", limit: 1)

    expect(hits.length).to eq(1)
    expect(hits.first[:slug]).to eq("climbing")
    expect(hits.first).to include(:name, :brief, :body, :domain)
  end

  it "scopes retrieval to a single domain when given" do
    vec = Array.new(1536, 0.0).tap { |arr| arr[0] = 1.0 }

    RuleEmbedding.create!(slug: "climbing", domain: "exploration", name: "Climbing",
                          brief: "x", body: "x", text_digest: "a", embedding: vec)
    RuleEmbedding.create!(slug: "diplomacy", domain: "social", name: "Diplomacy",
                          brief: "y", body: "y", text_digest: "b", embedding: vec)

    allow(ai).to receive(:embeddings).and_return([vec])

    hits = described_class.call(
      ai: ai, log: log, query_text: "anything", limit: 5, domain: "social"
    )

    expect(hits.map { |h| h[:slug] }).to eq(["diplomacy"])
  end

  it "returns [] for empty query without embedding" do
    expect(ai).not_to receive(:embeddings)

    expect(described_class.call(ai: ai, log: log, query_text: "  ")).to eq([])
  end

  it "returns [] and reports the error if embedding raises" do
    allow(ai).to receive(:embeddings).and_raise(DungeonMaster::AiError, "boom")

    expect(log).to receive(:report_error).with(
      instance_of(DungeonMaster::AiError),
      context: hash_including(step: "rules_lookup")
    )

    expect(described_class.call(ai: ai, log: log, query_text: "hi")).to eq([])
  end

  it "logs a rules_retrieved play_log entry with hit shape" do
    vec = Array.new(1536, 0.0).tap { |arr| arr[0] = 1.0 }
    RuleEmbedding.create!(slug: "climbing", domain: "exploration", name: "Climbing",
                          brief: "x", body: "x", text_digest: "a", embedding: vec)
    allow(ai).to receive(:embeddings).and_return([vec])

    expect(log).to receive(:play_log!).with(
      "rules_retrieved",
      a_string_including("retrieved 1 rule"),
      hash_including(parsed_response: hash_including(:hits, :limit, :query_text))
    )

    described_class.call(ai: ai, log: log, query_text: "I climb the wall", limit: 1)
  end
end
