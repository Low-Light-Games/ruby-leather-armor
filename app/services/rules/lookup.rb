# frozen_string_literal: true

require 'digest'

module Rules
  class Lookup
    DEFAULT_LIMIT = 4
    HYBRID_FLAG = :hybrid_rules_retrieval
    CANDIDATE_POOL = 20

    # Shared with the eval, so it scores what production serves.
    def self.fuse(vector_slugs, keyword_slugs)
      Retrieval::ReciprocalRankFusion.fuse(vector_slugs, keyword_slugs)
    end

    def self.call(ai:, log:, query_text:, limit: DEFAULT_LIMIT, domain: nil)
      new(ai: ai, log: log, query_text: query_text,
          limit: limit, domain: domain).call
    end

    def initialize(ai:, log:, query_text:, limit:, domain:)
      @ai         = ai
      @log        = log
      @query_text = query_text.to_s
      @limit      = sanitize_limit(limit)
      @domain     = domain&.to_s.presence
    end

    def call
      return [] if @query_text.strip.empty?

      hits = hybrid? ? hybrid_hits : vector_hits
      return [] if hits.nil?

      emit_retrieval_play_log(hits)
      hits
    rescue StandardError => e
      @log&.report_error(e, context: error_context_payload)
      []
    end

    private

    def hybrid?
      return @hybrid if defined?(@hybrid)

      @hybrid = FeatureFlag.enabled_for?(HYBRID_FLAG, nil)
    end

    def vector_hits
      query_embedding = embed_query
      return nil if query_embedding.nil?

      nearest_neighbors(query_embedding)
    end

    # If embedding fails, the keyword ranking still answers on its own.
    def hybrid_hits
      query_embedding = embed_query_or_nil
      vector_rows  = query_embedding ? scoped_rules.nearest_to(query_embedding, limit: CANDIDATE_POOL).to_a : []
      keyword_rows = scoped_rules.keyword_ranked(@query_text, limit: CANDIDATE_POOL).to_a

      rows_by_slug = (keyword_rows + vector_rows).index_by(&:slug)
      distances    = vector_rows.to_h { |row| [row.slug, row.neighbor_distance] }

      self.class.fuse(vector_rows.map(&:slug), keyword_rows.map(&:slug)).first(@limit).map do |slug, score|
        rule_hit(rows_by_slug.fetch(slug), distance: distances[slug]).merge(rrf_score: score.round(6))
      end
    end

    def embed_query_or_nil
      embed_query
    rescue Ai::Error
      nil
    end

    def scoped_rules
      @domain ? RuleEmbedding.for_domain(@domain) : RuleEmbedding.all
    end

    def rule_hit(row, distance:)
      {
        slug: row.slug,
        domain: row.domain,
        name: row.name,
        brief: row.brief,
        body: row.body,
        distance: distance
      }
    end

    def sanitize_limit(limit)
      n = limit.to_i
      n.positive? ? n : DEFAULT_LIMIT
    end

    def embed_query
      cache = embedding_cache
      if cache&.has?(text: @query_text, model: embedding_model, dimensions: embedding_dimensions)
        return cache.get(text: @query_text, model: embedding_model, dimensions: embedding_dimensions)
      end

      vectors = @log.timed_embedding_call(
        "RulesLookup query — #{@query_text.truncate(80)}",
        model_used: embedding_model,
        source: 'rules_lookup',
        ai: @ai
      ) do
        @ai.embeddings(**embeddings_kwargs)
      end

      vector = vectors.first
      cache&.store(text: @query_text, model: embedding_model,
                   dimensions: embedding_dimensions, vector: vector)
      vector
    end

    def embedding_cache
      @log.respond_to?(:embedding_cache) ? @log.embedding_cache : nil
    end

    def embeddings_kwargs
      kwargs = { texts: [@query_text], model: embedding_model }
      kwargs[:dimensions] = embedding_dimensions if embedding_dimensions
      kwargs
    end

    def embedding_model
      @embedding_model ||= DmConfig.instance.narrative_facts_embedding_model
    end

    def embedding_dimensions
      return @embedding_dimensions if defined?(@embedding_dimensions)

      @embedding_dimensions = DmConfig.instance.narrative_facts_embedding_dimensions
    end

    def nearest_neighbors(query_embedding)
      scoped_rules.nearest_to(query_embedding, limit: @limit).map do |row|
        rule_hit(row, distance: row.try(:neighbor_distance))
      end
    end

    def emit_retrieval_play_log(hits)
      return unless @log.respond_to?(:play_log!)

      @log.play_log!(
        'rules_retrieved',
        "Rules RAG retrieved #{hits.length} rule(s) for intent",
        parsed_response: {
          query_text: @query_text.truncate(160),
          limit: @limit,
          domain: @domain,
          retrieval: hybrid? ? 'hybrid' : 'vector',
          hits: hits.map { |h| h.slice(:slug, :domain, :distance, :rrf_score) }
        }
      )
    end

    def error_context_payload
      {
        step: 'rules_lookup',
        source: 'rules_lookup',
        query_preview: @query_text.truncate(120),
        limit: @limit,
        domain: @domain
      }
    end
  end
end
