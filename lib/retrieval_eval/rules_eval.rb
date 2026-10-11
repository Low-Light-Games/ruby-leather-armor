# frozen_string_literal: true

require "base64"
require "digest"

module RetrievalEval
  # Offline retrieval eval for Rules::Lookup: labelled player intents
  # (rules_queries.yml) scored for every variant in RulesVariants at the
  # production cut-off (Rules::Lookup::DEFAULT_LIMIT).
  #
  # Nothing here calls OpenAI. Vectors come from rules_vectors.json, written by
  # scripts/retrieval_eval/embed_openai.rb with production's embedding model
  # (text-embedding-3-small, 1536-d), keyed by SHA1 of the exact text embedded.
  # The vector ranking is an exact cosine scan in Ruby (the order an HNSW scan
  # returns at ~51 rows); the keyword ranking is the production
  # RuleEmbedding.keyword_ranked query against Postgres, and plain RRF is the
  # production Rules::Lookup.fuse, so the eval scores the code that ships.
  #
  # Queries are split once into dev and test halves (stratified by slice and
  # source, fixed seed). Variants are compared on dev, at most one is picked,
  # and only test numbers are used to judge it (see RulesReport).
  class RulesEval
    DIR = Pathname(__dir__)
    QUERIES_PATH = DIR.join("rules_queries.yml")
    VECTORS_PATH = DIR.join("rules_vectors.json")
    SOURCES = %w[playtest written].freeze
    SLICES = %w[jargon paraphrase].freeze
    SPLIT_SEED = 200

    class StaleFixtures < StandardError; end
    class InvalidQueries < StandardError; end

    def self.run(cutoff: Rules::Lookup::DEFAULT_LIMIT)
      new(cutoff: cutoff).run
    end

    # Reads and validates the labelled queries: [{text:, relevant:, source:, slice:}].
    def self.load_queries(path = QUERIES_PATH, known_slugs: Rules.all_entries.keys)
      rows = YAML.safe_load_file(path)
      raise InvalidQueries, "#{path} must be a list of queries" unless rows.is_a?(Array)

      queries = rows.map { |row| parse_query(row, known_slugs) }
      duplicates = queries.map { |q| q[:text] }.tally.select { |_text, count| count > 1 }.keys
      raise InvalidQueries, "duplicate queries: #{duplicates.inspect}" if duplicates.any?

      queries
    end

    def self.parse_query(row, known_slugs)
      text = row["query"].to_s
      relevant = Array(row["relevant"])
      problem = query_problem(text, relevant, row, known_slugs)
      raise InvalidQueries, problem if problem

      { text: text, relevant: relevant, source: row["source"], slice: row["slice"] }
    end

    def self.query_problem(text, relevant, row, known_slugs)
      unknown = relevant - known_slugs
      if text.strip.empty? then "query text is blank: #{row.inspect}"
      elsif relevant.empty? then "#{text.inspect} has no relevant rules"
      elsif unknown.any? then "#{text.inspect} labels unknown rule(s) #{unknown.inspect}"
      elsif !SOURCES.include?(row["source"]) then "#{text.inspect} has source #{row['source'].inspect}"
      elsif !SLICES.include?(row["slice"]) then "#{text.inspect} has slice #{row['slice'].inspect}"
      end
    end
    private_class_method :parse_query, :query_problem

    # Assigns each query to :dev or :test, ~50/50 within every slice x source
    # stratum. The order inside a stratum is by SHA1 of the query text, so
    # relabelling never moves a query between halves; adding or editing query
    # text can.
    def self.split(queries, seed: SPLIT_SEED)
      rng = Random.new(seed)
      assignment = {}
      queries.group_by { |q| [q[:slice], q[:source]] }.sort_by(&:first).each do |_stratum, members|
        shuffled = members.sort_by { |q| Digest::SHA1.hexdigest(q[:text]) }.shuffle(random: rng)
        dev_size = shuffled.size / 2
        shuffled.each_with_index { |q, i| assignment[q[:text]] = i < dev_size ? :dev : :test }
      end
      queries.map { |q| q.merge(split: assignment.fetch(q[:text])) }
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
        results = self.class.split(self.class.load_queries).map { |query| score_query(query) }
        raise ActiveRecord::Rollback
      end
      RulesReport.new(results, cutoff: @cutoff, model: fixtures.fetch("model"))
    end

    private

    def score_query(query)
      vector = vector_ranking(query[:text])
      keyword = RuleEmbedding.keyword_ranked(query[:text], limit: Rules::Lookup::CANDIDATE_POOL).map(&:slug)
      rankings = RulesVariants.all.transform_values { |variant| variant.call(vector, keyword, query[:text]) }

      query.merge(rankings: rankings, jargon_detected: RulesVariants.jargon?(query[:text]))
    end

    # [[slug, cosine], ...], best first.
    def vector_ranking(text)
      query_vector = vector_for(text)
      corpus.map { |doc| [doc[:slug], cosine(query_vector, doc[:vector])] }.sort_by { |slug, score| [-score, slug] }
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

    def vector_for(text)
      packed = fixtures.fetch("vectors").fetch(Digest::SHA1.hexdigest(text)) do
        raise StaleFixtures, "no fixture vector for #{text.truncate(60).inspect}; rule text or queries changed. " \
                             "Regenerate: ruby scripts/retrieval_eval/embed_openai.rb"
      end
      Base64.strict_decode64(packed).unpack("e*")
    end

    def fixtures
      @fixtures ||= JSON.parse(VECTORS_PATH.read)
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
  end
end
