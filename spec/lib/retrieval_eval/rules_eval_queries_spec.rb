require "rails_helper"
require "tempfile"

RSpec.describe RetrievalEval::RulesEval do
  def load_yaml(rows)
    Tempfile.create(["queries", ".yml"]) do |file|
      file.write(JSON.generate(rows)) # JSON is YAML, and has no aliases
      file.flush
      described_class.load_queries(file.path, known_slugs: %w[charge swim])
    end
  end

  let(:row) { { "query" => "I charge", "relevant" => %w[charge], "source" => "playtest", "slice" => "jargon" } }

  describe ".load_queries" do
    it "parses text, labels, source and slice" do
      expect(load_yaml([row])).to eq([{ text: "I charge", relevant: %w[charge], source: "playtest", slice: "jargon" }])
    end

    it "rejects unknown rule slugs, sources and slices, and duplicate queries" do
      expect { load_yaml([row.merge("relevant" => %w[fly])]) }.to raise_error(described_class::InvalidQueries, /fly/)
      expect { load_yaml([row.merge("source" => "forum")]) }.to raise_error(described_class::InvalidQueries, /source/)
      expect { load_yaml([row.merge("slice" => "other")]) }.to raise_error(described_class::InvalidQueries, /slice/)
      expect { load_yaml([row, row]) }.to raise_error(described_class::InvalidQueries, /duplicate/)
      expect { load_yaml([row.merge("relevant" => [])]) }.to raise_error(described_class::InvalidQueries, /no relevant/)
    end

    it "loads the committed set with every query tagged" do
      queries = described_class.load_queries

      expect(queries.size).to eq(156)
      expect(queries.map { |q| q[:source] }.tally).to eq("playtest" => 91, "written" => 65)
      expect(queries.map { |q| q[:slice] }.tally).to eq("jargon" => 51, "paraphrase" => 105)
    end
  end

  describe ".split" do
    let(:queries) { described_class.load_queries }

    it "halves every slice x source stratum, deterministically" do
      split = described_class.split(queries)

      expect(described_class.split(queries)).to eq(split)
      split.group_by { |q| [q[:slice], q[:source]] }.each_value do |members|
        dev = members.count { |q| q[:split] == :dev }
        expect(dev).to eq(members.size / 2)
      end
    end

    it "does not move queries between halves when labels change" do
      relabelled = queries.map { |q| q.merge(relevant: %w[charge]) }

      expect(described_class.split(relabelled).map { |q| q[:split] })
        .to eq(described_class.split(queries).map { |q| q[:split] })
    end
  end
end
