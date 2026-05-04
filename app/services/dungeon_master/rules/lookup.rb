# frozen_string_literal: true

require 'digest'

module DungeonMaster
  module Rules
    # Retrieves the top-K rule entries most relevant to a free-text intent
    # via pgvector cosine similarity over `rule_embeddings`. Used by the
    # RollRequest step in place of the static rules-manifest dump.
    #
    # Mirrors the ergonomics of `DungeonMaster::Lore::FactsLookup`:
    # callers pass an `ai` client and a `log` so the embedding round-trip
    # is recorded as an `embedding` AiLog row and any failure is reported
    # to Sentry via `report_error`.
    #
    # Returns an array of plain hashes (slug, name, domain, brief, body,
    # distance) so the caller can stitch them into a prompt without
    # carrying ActiveRecord rows around. Returns an empty array on any
    # failure — the pipeline never crashes because rules retrieval failed.
    class Lookup
      DEFAULT_LIMIT = 4

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

        query_embedding = embed_query
        return [] if query_embedding.nil?

        hits = nearest_neighbors(query_embedding)
        emit_retrieval_play_log(hits)
        hits
      rescue StandardError => e
        @log&.report_error(e, context: error_context_payload)
        []
      end

      # `Lore::FactsLookup` uses a `Lore::ErrorContext` value object; this
      # service is small enough that an inline hash carries its weight.
      # Keep the shape stable so Sentry filters and the rules_retrieved
      # play_log can be cross-referenced.

      private

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
        scope = RuleEmbedding.all
        scope = scope.for_domain(@domain) if @domain
        scope.nearest_to(query_embedding, limit: @limit).map do |row|
          {
            slug: row.slug,
            domain: row.domain,
            name: row.name,
            brief: row.brief,
            body: row.body,
            distance: row.try(:neighbor_distance)
          }
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
            hits: hits.map { |h| h.slice(:slug, :domain, :distance) }
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
end
