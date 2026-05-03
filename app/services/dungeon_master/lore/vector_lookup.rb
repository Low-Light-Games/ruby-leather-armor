# frozen_string_literal: true

module DungeonMaster
  module Lore
    class VectorLookup
      def self.call(adventure:, ai:, log:, query_text:, limit: nil)
        new(adventure: adventure, ai: ai, log: log,
            query_text: query_text, limit: limit).call
      end

      def initialize(adventure:, ai:, log:, query_text:, limit: nil)
        @adventure  = adventure
        @ai         = ai
        @log        = log
        @query_text = query_text.to_s
        @limit      = sanitize_limit(limit)
      end

      def call
        return [] if @query_text.strip.empty?

        query_embedding = embed_query
        return [] if query_embedding.nil?

        hits = nearest_neighbor_hits(query_embedding)
        emit_retrieval_play_log(hits)
        hits
      rescue StandardError => e
        @log.report_error(e, context: error_context.with(query_preview: @query_text.truncate(120)))
        []
      end

      private

      # Required subclass overrides ---------------------------------------

      def lookup_kind          = raise NotImplementedError
      def hit_class            = raise NotImplementedError
      def play_log_event_class = raise NotImplementedError
      def play_log_event_type  = raise NotImplementedError
      def query_neighbors(_query_embedding) = raise NotImplementedError

      # Shared --------------------------------------------------------

      def nearest_neighbor_hits(query_embedding)
        query_neighbors(query_embedding).map { |row| hit_class.from_row(row).to_h }
      end

      def emit_retrieval_play_log(hits)
        @log.play_log!(
          play_log_event_type,
          play_log_summary(hits),
          parsed_response: play_log_event_class.new(
            query_text: @query_text,
            limit:      @limit,
            hits:       hits,
          ).to_h,
        )
      end

      def play_log_summary(hits)
        "Retrieved #{hits.length} #{lookup_kind} hit(s) for query"
      end

      def embed_query
        vectors = @log.timed_embedding_call(
          "#{lookup_source} query — #{@query_text.truncate(80)}",
          model_used: embedding_model,
          source:     lookup_source,
          ai:         @ai,
        ) do
          @ai.embeddings(**embeddings_kwargs)
        end

        vectors.first
      end

      def lookup_source = "#{lookup_kind}_lookup"

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

      def sanitize_limit(limit)
        raw = limit.presence || DmConfig.instance.narrative_facts_top_k
        n = raw.to_i
        n.positive? ? n : 8
      end

      def error_context
        @error_context ||= ErrorContext.new(
          step:         lookup_source,
          adventure_id: @adventure&.id,
          loop_id:      nil,
          source:       lookup_source,
        )
      end
    end
  end
end
