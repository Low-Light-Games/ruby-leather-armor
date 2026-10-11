# frozen_string_literal: true

require "base64"
require "digest"

module RetrievalEval
  # Offline eval of Rules::Lookup: committed vectors, plus production's keyword
  # query and fusion, scored on labelled intents split into dev and test.
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

    # Ordered by text hash, so relabelling never moves a query between halves.
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

    # Always rolled back: the eval neither depends on nor disturbs rule_embeddings.
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
