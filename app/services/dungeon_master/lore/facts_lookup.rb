# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Code-only fact retriever: embeds the player's stated intent, runs a
    # pgvector cosine-similarity search (via `neighbor`) scoped to the
    # current adventure's *active* facts, and returns the top-K hits as
    # plain hashes ready for the `sanity_checker_world` prompt.
    #
    # This is the *read* side of the narrative facts store — the mirror
    # of `Lore::ApplyResults`' write side, and the third and final
    # embedding-call site after `ApplyResults` (write) and
    # `SeedFromAdventure` (one-shot creation). Read calls share the same
    # batched `AiClient#embeddings` API used on the write path (a
    # 1-element `texts:` array — the OpenAI embeddings endpoint accepts
    # arrays of any length, so there is no separate single-text API).
    #
    # AiLog ownership matches the rest of the repo: `AiClient` only
    # holds HTTP + retry, and this service is the read-side owner of
    # the `call_type: "embedding"` AiLog row (the write-side owner is
    # `Lore::ApplyResults`, C5). `AiClient` itself does not write
    # AiLog rows — that keeps the config/transport class free of
    # adventure/user/registry context it does not otherwise need.
    #
    # A `narrative_facts_retrieved` play_log event is emitted with the
    # K hits + their distances so the Admin UI facts-retrieval panel
    # (future work) can surface the exact retrieval for a given turn.
    #
    # Failure policy: if the embeddings API call or the pgvector query
    # raises, we call `log.report_error` and return an empty array.
    # The world check degrades to zero retrieved facts — which is the
    # same input shape as a brand-new adventure before the seed pass
    # populates anything, and which the sanity_checker_world prompt
    # already has to handle gracefully. Lossy-with-Sentry, per
    # [.cursor/rules/error-reporting-sentry.mdc].
    #
    # Inert for C9 — no live caller invokes this yet. `SanityChecker`
    # wires it in via C10's cutover commit.
    class FactsLookup
      EMBEDDING_MODEL = "text-embedding-3-small"

      Hit = Struct.new(:fact_id, :text, :kind, :polarity, :distance, keyword_init: true)

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
        @log.report_error(e, context: {
          step: "facts_lookup",
          adventure_id: @adventure&.id,
          query_preview: @query_text.to_s.truncate(120),
        })
        []
      end

      private

      def sanitize_limit(limit)
        raw = limit.presence || DmConfig.instance.narrative_facts_top_k
        n = raw.to_i
        n.positive? ? n : 8
      end

      def embed_query
        prompt_summary = "FactsLookup query — #{@query_text.truncate(80)}"

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        vectors = @ai.embeddings(texts: [@query_text], model: EMBEDDING_MODEL)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        @log.ai_log!(
          "embedding",
          prompt_summary,
          nil,
          { text_count: 1, dim: vectors.first&.length, source: "facts_lookup" },
          parse_status: "success",
          model_used:   EMBEDDING_MODEL,
          duration_ms:  duration_ms,
        )

        vectors.first
      rescue DungeonMaster::AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!(
          "embedding",
          "FactsLookup query — #{@query_text.truncate(80)}",
          e,
          model_used:  EMBEDDING_MODEL,
          duration_ms: duration_ms,
        )
        raise
      end

      def nearest_neighbors(query_embedding)
        AdventureNarrativeFact
          .active
          .where(adventure_id: @adventure.id)
          .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
          .limit(@limit)
          .map do |row|
            Hit.new(
              fact_id:  row.id,
              text:     row.text,
              kind:     row.kind,
              polarity: row.polarity,
              distance: row.neighbor_distance,
            ).to_h
          end
      end

      def emit_retrieval_play_log(hits)
        @log.play_log!(
          "narrative_facts_retrieved",
          "World check retrieved #{hits.length} fact(s) for intent",
          parsed_response: {
            query_preview: @query_text.to_s.truncate(120),
            limit: @limit,
            hits: hits.map { |h| h.slice(:fact_id, :kind, :distance) },
          },
        )
      end
    end
  end
end
