require "rails_helper"

RSpec.describe RetrievalEval::RulesEval do
  subject(:report) { described_class.run }

  it "keeps recall at the production cut-off above the recorded floors" do
    expect(report.metrics[:vector][:recall_at_k]).to be >= 0.76
    expect(report.metrics[:keyword][:recall_at_k]).to be >= 0.49
    expect(report.metrics[:rrf][:recall_at_k]).to be >= 0.68
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
