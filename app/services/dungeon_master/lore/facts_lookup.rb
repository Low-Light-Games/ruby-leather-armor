# frozen_string_literal: true

module DungeonMaster
  module Lore
    class FactsLookup
      def self.call(adventure:, ai:, log:, query_text:, limit: nil)
        new(adventure: adventure, ai: ai, log: log,
            query_text: query_text, limit: limit).call
      end

      def initialize(adventure:, ai:, log:, query_text:, limit: nil)
        @adventure   = adventure
        @ai          = ai
        @log         = log
        @query_text  = query_text.to_s
        @limit       = sanitize_limit(limit)
      end

      def call
        return [] if @query_text.strip.empty?

        query_embedding = embed_query
        return [] if query_embedding.nil?

        hits = nearest_neighbors(query_embedding)
        emit_retrieval_play_log(hits)
        hits
      rescue StandardError => e
        @log.report_error(e, context: error_context.with(query_preview: @query_text.truncate(120)))
        []
      end

      private

      def sanitize_limit(limit)
        raw = limit.presence || DmConfig.instance.narrative_facts_top_k
        n = raw.to_i
        n.positive? ? n : 8
      end

      def embed_query
        vectors = @log.timed_embedding_call(
          "FactsLookup query — #{@query_text.truncate(80)}",
          model_used: embedding_model,
          source:     "facts_lookup",
        ) do
          @ai.embeddings(**embeddings_kwargs)
        end

        vectors.first
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
        AdventureNarrativeFact
          .nearest_active_for(@adventure, query_embedding, limit: @limit)
          .map { |row| FactHit.from_row(row).to_h }
      end

      def emit_retrieval_play_log(hits)
        @log.play_log!(
          "narrative_facts_retrieved",
          "World check retrieved #{hits.length} fact(s) for intent",
          parsed_response: PlayLogEvents::FactsRetrieved.new(
            query_text: @query_text,
            limit:      @limit,
            hits:       hits.map { |h| h.slice(:fact_id, :kind, :distance) },
          ).to_h,
        )
      end

      def error_context
        @error_context ||= ErrorContext.new(
          step:         "facts_lookup",
          adventure_id: @adventure&.id,
          loop_id:      nil,
          source:       "facts_lookup",
        )
      end
    end
  end
end
