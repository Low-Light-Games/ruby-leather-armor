require "rails_helper"

# Offline eval of Rules::Lookup's retrieval (see lib/retrieval_eval). The
# fixtures are deterministic, so these floors only move when the rule text,
# the labelled queries or the retrieval code change: a drop is a regression
# to explain, a rise means the floor can be raised.
RSpec.describe RetrievalEval::RulesEval do
  subject(:report) { described_class.run }

  it "has a fixture vector for every rule and query" do
    expect { report }.not_to raise_error
  end

  it "scores every labelled query in all three modes" do
    expect(report.results.size).to eq(48)
    expect(report.metrics.keys).to eq(%i[vector keyword hybrid])
  end

  it "keeps recall at the production cut-off above the recorded floors" do
    expect(report.cutoff).to eq(Rules::Lookup::DEFAULT_LIMIT)
    expect(report.metrics[:vector][:recall_at_k]).to be >= 0.79
    expect(report.metrics[:keyword][:recall_at_k]).to be >= 0.63
    expect(report.metrics[:hybrid][:recall_at_k]).to be >= 0.77
  end

  it "leaves rule_embeddings untouched" do
    RuleEmbedding.create!(slug: "keep_me", domain: "combat", name: "Keep", body: "x", text_digest: "d")

    report

    expect(RuleEmbedding.pluck(:slug)).to eq(["keep_me"])
  end
end
