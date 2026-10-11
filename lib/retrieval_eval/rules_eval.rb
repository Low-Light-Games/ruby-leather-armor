# frozen_string_literal: true

require "digest"

module RetrievalEval
  # Offline retrieval eval for Rules::Lookup: labelled player intents
  # (rules_queries.yml) scored for vector-only, keyword-only and hybrid (RRF)
  # retrieval at the production cut-off (Rules::Lookup::DEFAULT_LIMIT).
  #
  # Nothing here calls OpenAI. Vectors come from rules_vectors.json, produced
  # once by scripts/retrieval_eval/embed_fixtures.py with a free local model
  # (bge-small-en-v1.5, 384-d); since rule_embeddings stores 1536-d vectors,
  # the vector ranking is an exact cosine scan in Ruby (the same ordering an
  # HNSW scan returns at ~51 rows). The keyword ranking is the production
  # RuleEmbedding.keyword_ranked query against Postgres, and fusion is the
  # production Rules::Lookup.fuse, so the eval scores the code that ships.
  class RulesEval
    DIR = Pathname(__dir__)
    QUERIES_PATH = DIR.join("rules_queries.yml")
    VECTORS_PATH = DIR.join("rules_vectors.json")
    MODES = %i[vector keyword hybrid].freeze

    class StaleFixtures < StandardError; end

    def self.run(cutoff: Rules::Lookup::DEFAULT_LIMIT)
      new(cutoff: cutoff).run
    end

    def initialize(cutoff:)
      @cutoff = cutoff
    end

    # Loads the rule corpus into rule_embeddings inside a transaction that is
    # always rolled back, so the eval never depends on (or disturbs) whatever
    # rules:embed last wrote.
    def run
      results = nil
      RuleEmbedding.transaction(requires_new: true) do
        load_corpus!
        results = queries.map { |query| score_query(query) }
        raise ActiveRecord::Rollback
      end
      Report.new(results, cutoff: @cutoff)
    end

    private

    def score_query(query)
      rankings = {
        vector: vector_ranking(query[:text]),
        keyword: RuleEmbedding.keyword_ranked(query[:text], limit: Rules::Lookup::CANDIDATE_POOL).map(&:slug)
      }
      pool = Rules::Lookup::CANDIDATE_POOL
      rankings[:hybrid] = Rules::Lookup.fuse(rankings[:vector].first(pool), rankings[:keyword]).map(&:first)

      { text: query[:text], relevant: query[:relevant], rankings: rankings }
    end

    def vector_ranking(text)
      query_vector = vector_for(text)
      corpus.sort_by { |doc| -cosine(query_vector, doc[:vector]) }.map { |doc| doc[:slug] }
    end

    def load_corpus!
      RuleEmbedding.delete_all
      now = Time.current
      RuleEmbedding.insert_all!(
        Rules.all_entries.map do |slug, entry|
          { slug: slug, domain: entry[:domain], name: entry[:name], brief: Rules.brief_for(entry),
            body: entry[:text].to_s, text_digest: "eval", created_at: now, updated_at: now }
        end
      )
    end

    def corpus
      @corpus ||= Rules.all_entries.map do |slug, entry|
        { slug: slug, vector: vector_for(Rules.embedding_text(entry)) }
      end
    end

    def queries
      @queries ||= YAML.safe_load_file(QUERIES_PATH).map do |row|
        unknown = row["relevant"] - Rules.all_entries.keys
        raise StaleFixtures, "#{row['query'].inspect} labels unknown rule(s) #{unknown.inspect}" if unknown.any?

        { text: row["query"], relevant: row["relevant"] }
      end
    end

    def vector_for(text)
      vectors.fetch(Digest::SHA1.hexdigest(text)) do
        raise StaleFixtures, "no fixture vector for #{text.truncate(60).inspect}; rule text or queries changed. " \
                             "Regenerate: see scripts/retrieval_eval/embed_fixtures.py"
      end
    end

    def vectors
      @vectors ||= JSON.parse(VECTORS_PATH.read).fetch("vectors")
    end

    def cosine(a, b)
      dot = 0.0
      norm_a = 0.0
      norm_b = 0.0
      a.each_with_index do |x, i|
        y = b[i]
        dot += x * y
        norm_a += x * x
        norm_b += y * y
      end
      dot / Math.sqrt(norm_a * norm_b)
    end

    # Metrics per mode, averaged over queries:
    #   hit@1    - the top result is one of the labelled rules
    #   recall@k - share of labelled rules inside the top k (what the prompt sees)
    #   mrr      - 1 / rank of the first labelled rule (0 if absent)
    class Report
      attr_reader :results, :cutoff

      def initialize(results, cutoff:)
        @results = results
        @cutoff = cutoff
      end

      def metrics
        @metrics ||= MODES.index_with do |mode|
          {
            hit_at_1: mean { |r| r[:relevant].include?(r[:rankings][mode].first) ? 1.0 : 0.0 },
            recall_at_k: mean { |r| (r[:rankings][mode].first(cutoff) & r[:relevant]).size.fdiv(r[:relevant].size) },
            mrr: mean { |r| reciprocal_rank(r[:rankings][mode], r[:relevant]) }
          }
        end
      end

      def to_s
        lines = ["Rules retrieval eval: #{results.size} queries, cut-off k=#{cutoff}", "",
                 format("%-8s %8s %10s %8s", "mode", "hit@1", "recall@#{cutoff}", "mrr")]
        metrics.each do |mode, m|
          lines << format("%-8s %8.3f %10.3f %8.3f", mode, m[:hit_at_1], m[:recall_at_k], m[:mrr])
        end
        lines.concat(["", "Queries where hybrid and vector disagree on the top #{cutoff}:"])
        disagreements.each do |r|
          lines << "  #{r[:text].inspect} (want #{r[:relevant].join(', ')})"
          lines << "    vector: #{r[:rankings][:vector].first(cutoff).join(', ')}"
          lines << "    hybrid: #{r[:rankings][:hybrid].first(cutoff).join(', ')}"
        end
        lines.join("\n")
      end

      private

      def disagreements
        results.reject { |r| r[:rankings][:vector].first(cutoff) == r[:rankings][:hybrid].first(cutoff) }
      end

      def reciprocal_rank(ranking, relevant)
        index = ranking.index { |slug| relevant.include?(slug) }
        index ? 1.0 / (index + 1) : 0.0
      end

      def mean(&block)
        results.sum(&block) / results.size
      end
    end
  end
end
