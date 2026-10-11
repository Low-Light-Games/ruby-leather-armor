# frozen_string_literal: true

module RetrievalEval
  # The retrieval variants the rules eval compares. They were declared here
  # before any of them was scored on the dev split; do not add or retune one
  # after looking at test results.
  #
  # Each variant maps a query's two rankings to a final ranking (slugs, best
  # first):
  #   vector: [[slug, cosine], ...] over the whole corpus, best first
  #   keyword: slugs from RuleEmbedding.keyword_ranked, best first (top POOL)
  #
  # "fallback" (keyword only when embedding the query fails, today's outage
  # behaviour) is not listed: whenever the embedding succeeds it returns the
  # vector ranking, so it scores exactly like `vector`; during an outage it
  # serves the `keyword` ranking.
  module RulesVariants
    POOL = Rules::Lookup::CANDIDATE_POOL

    # Router: words of art that mark a query as rules jargon, on top of the
    # words in rule names. Detected from the query text only, never the label.
    JARGON_TERMS = /\b(ac|cmd|cmb|hp|aoo|dc|bab|take (10|20)|flat-footed|flank\w*|stealth\w*|cover|provok\w*|
                     thieves'? tools|tumbl\w*|cantrip|overencumbered|5-foot|five-foot)\b/ix
    NAME_STOPWORDS = %w[and of for the use using skill rules during checks check scale shifts information
                        another cha wis str dex spell].freeze

    module_function

    # name => lambda(vector, keyword, text) -> slugs. Order is the report order.
    def all
      {
        vector: ->(vector, _keyword, _text) { vector.map(&:first) },
        keyword: ->(_vector, keyword, _text) { keyword },
        rrf: ->(vector, keyword, _text) { rrf(vector, keyword) },
        wrrf_2to1: ->(vector, keyword, _text) { rrf(vector, keyword, weights: [2, 1]) },
        wrrf_3to1: ->(vector, keyword, _text) { rrf(vector, keyword, weights: [3, 1]) },
        wrrf_4to1: ->(vector, keyword, _text) { rrf(vector, keyword, weights: [4, 1]) },
        tiebreak_005: ->(vector, keyword, _text) { tie_break(vector, keyword, epsilon: 0.005) },
        tiebreak_010: ->(vector, keyword, _text) { tie_break(vector, keyword, epsilon: 0.010) },
        tiebreak_020: ->(vector, keyword, _text) { tie_break(vector, keyword, epsilon: 0.020) },
        router: ->(vector, keyword, text) { jargon?(text) ? rrf(vector, keyword) : vector.map(&:first) }
      }
    end

    # Production RRF (k = 60) over the same candidate pools Rules::Lookup uses.
    def rrf(vector, keyword, weights: nil)
      vector_slugs = vector.first(POOL).map(&:first)
      fused = if weights
                Retrieval::ReciprocalRankFusion.fuse(vector_slugs, keyword, weights: weights)
              else
                Rules::Lookup.fuse(vector_slugs, keyword)
              end
      fused.map(&:first)
    end

    # Vector order, except that rules whose cosine is within `epsilon` of the
    # first rule of their run are re-ordered by keyword rank (unmatched last).
    def tie_break(vector, keyword, epsilon:)
      keyword_rank = keyword.each_with_index.to_h
      remaining = vector
      ordered = []
      until remaining.empty?
        head_score = remaining.first.last
        run = remaining.take_while { |_slug, score| head_score - score <= epsilon }
        remaining = remaining.drop(run.size)
        ordered.concat(run.each_with_index.sort_by { |(slug, _), i| [keyword_rank.fetch(slug, Float::INFINITY), i] }
                          .map { |(slug, _), _| slug })
      end
      ordered
    end

    def jargon?(text)
      words = text.downcase.scan(/[a-z0-9-]+/).map { |word| stem(word) }
      text.match?(JARGON_TERMS) || words.intersect?(rule_name_stems)
    end

    def rule_name_stems
      @rule_name_stems ||= begin
        names = Rules.all_entries.values.map { |entry| entry[:name].gsub(/\(.*?\)/, " ").downcase }
        words = names.flat_map { |name| name.scan(/[a-z0-9-]+/) }
        words.map { |word| stem(word) }.uniq.reject { |word| NAME_STOPWORDS.include?(word) || word.size < 3 }
      end
    end

    def stem(word)
      word.sub(/(ing|es|s|ed)\z/, "")
    end
  end
end
