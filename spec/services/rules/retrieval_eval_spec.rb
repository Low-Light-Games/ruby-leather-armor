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

  it "scores every labelled query in every declared mode and splits them into dev and test" do
    expect(report.results.size).to eq(156)
    expect(report.modes).to eq(RetrievalEval::RulesVariants.all.keys)
    expect(report.dev.size + report.test.size).to eq(156)
    expect(report.test.size).to be_between(76, 80)
  end

  it "keeps recall at the production cut-off above the recorded floors" do
    expect(report.cutoff).to eq(Rules::Lookup::DEFAULT_LIMIT)
    expect(report.metrics[:vector][:recall_at_k]).to be >= 0.76
    expect(report.metrics[:keyword][:recall_at_k]).to be >= 0.49
    expect(report.metrics[:rrf][:recall_at_k]).to be >= 0.68
  end

  it "reports test-set CIs, differences from vector and McNemar p-values" do
    stats = report.test_stats

    expect(stats[:vector][:metrics][:recall_at_k][:ci].first).to be <= stats[:vector][:metrics][:recall_at_k][:mean]
    expect(stats[:rrf][:difference][:hit_at_1][:ci].size).to eq(2)
    expect(stats[:rrf][:mcnemar][:p]).to be_between(0, 1)
    expect(report.to_s).to include("TEST (", "Verdict:")
    expect { JSON.generate(report.as_json) }.not_to raise_error
  end

  it "fails loudly when a rule's text drifts from the committed vectors" do
    entries = Rules.all_entries.dup
    entries["charge"] = entries["charge"].merge(text: "#{entries['charge'][:text]} Edited.")
    allow(Rules).to receive(:all_entries).and_return(entries)

    expect { report }.to raise_error(described_class::StaleFixtures, /Charge/)
  end

  it "leaves rule_embeddings untouched" do
    RuleEmbedding.create!(slug: "keep_me", domain: "combat", name: "Keep", body: "x", text_digest: "d")

    report

    expect(RuleEmbedding.pluck(:slug)).to eq(["keep_me"])
  end
end
