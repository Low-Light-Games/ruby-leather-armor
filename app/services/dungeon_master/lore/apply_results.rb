# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Sole writer of `adventure_narrative_facts`. Contract, call sites, and
    # lossy-with-Sentry rationale live in docs/pipeline_steps.md Decision 37
    # and docs/design_philosophy.md §18.
    class ApplyResults
      EMBEDDING_MODEL = "text-embedding-3-small"

      def self.call(adventure:, loop:, log:, ai:, result:, source: "loremaster")
        new(adventure: adventure, loop: loop, log: log, ai: ai,
            result: result, source: source).call
      end

      def initialize(adventure:, loop:, log:, ai:, result:, source:)
        @adventure = adventure
        @loop = loop
        @log = log
        @ai = ai
        @result = result || {}
        @source = source
      end

      def call
        facts = normalized_facts
        invalidates = normalized_invalidates

        return ApplyOutcome.new([], []) if facts.empty? && invalidates.empty?

        embeddings_by_idx = embed_facts(facts)
        inserted_ids = insert_facts(facts, embeddings_by_idx)
        invalidated_ids = apply_invalidations(invalidates, inserted_ids)

        ApplyOutcome.new(inserted_ids.values.compact, invalidated_ids)
      end

      # Value returned to the caller so tests (and future observability
      # surfaces) can see what landed. Not used to drive behaviour.
      ApplyOutcome = Struct.new(:inserted_fact_ids, :invalidated_fact_ids)

      private

      def normalized_facts
        Array(@result["facts"] || @result[:facts]).select { |f| f.is_a?(Hash) }
      end

      def normalized_invalidates
        Array(@result["invalidates"] || @result[:invalidates]).select { |i| i.is_a?(Hash) }
      end

      def embed_facts(facts)
        return {} if facts.empty?

        texts = facts.map { |f| string_field(f, "text").to_s }

        if texts.any?(&:empty?)
          @log.report_error(
            ArgumentError.new("Loremaster emitted a fact with empty text"),
            context: error_context.merge(texts_preview: texts.first(3))
          )
        end

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          vectors = @ai.embeddings(texts: texts, model: EMBEDDING_MODEL)
        rescue DungeonMaster::AiError => e
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
          @log.ai_log_error!(
            "embedding",
            "Loremaster apply — #{texts.length} fact text(s)",
            e,
            model_used: EMBEDDING_MODEL,
            duration_ms: duration_ms,
          )
          @log.report_error(e, context: error_context.merge(source: "apply_results.embeddings"))
          raise
        end
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        @log.ai_log!(
          "embedding",
          "Loremaster apply — #{texts.length} fact text(s)",
          nil,
          { text_count: texts.length, dim: vectors.first&.length, source: @source },
          parse_status: "success",
          model_used: EMBEDDING_MODEL,
          duration_ms: duration_ms,
        )

        vectors.each_with_index.each_with_object({}) do |(vec, idx), acc|
          acc[idx] = vec
        end
      end

      def insert_facts(facts, embeddings_by_idx)
        inserted_ids = {}

        facts.each_with_index do |fact, idx|
          text = string_field(fact, "text")
          kind = string_field(fact, "kind")
          polarity = string_field(fact, "polarity").presence || "asserts"
          entities = Array(fact["entities"] || fact[:entities]).map(&:to_s)
          embedding = embeddings_by_idx[idx]

          begin
            row = AdventureNarrativeFact.create!(
              adventure_id: @adventure.id,
              text: text,
              kind: kind,
              entities: entities,
              polarity: polarity,
              embedding: embedding,
              introduced_at_loop_id: @loop&.id,
              source: @source,
              source_idx: idx,
            )
            inserted_ids[idx] = row.id
            @log.play_log!(
              "narrative_fact_stored",
              "#{@source}: stored #{kind} fact ##{row.id}",
              parsed_response: { fact_id: row.id, kind: kind, polarity: polarity,
                                 source: @source, source_idx: idx,
                                 text: @log.truncate(text) },
            )
          rescue ActiveRecord::RecordNotUnique
            # Partial unique index hit — an at-most-once retry for the
            # same (adventure, loop, source_idx) triple. Idempotent by
            # design; don't log it as an error, but also don't claim a
            # new fact was stored.
            existing = AdventureNarrativeFact.find_by(
              adventure_id: @adventure.id,
              introduced_at_loop_id: @loop&.id,
              source: @source,
              source_idx: idx,
            )
            inserted_ids[idx] = existing&.id
          rescue StandardError => e
            @log.report_error(
              e,
              context: error_context.merge(
                source: "apply_results.insert_fact",
                source_idx: idx,
                kind: kind,
                text_preview: text.to_s.first(80),
              )
            )
          end
        end

        inserted_ids
      end

      def apply_invalidations(invalidates, inserted_ids)
        invalidated_ids = []

        invalidates.each do |entry|
          fact_id = entry["fact_id"] || entry[:fact_id]
          next unless fact_id.is_a?(Integer) || fact_id.to_s =~ /\A\d+\z/

          replacement_idx = entry["replacement_source_idx"] || entry[:replacement_source_idx]
          replacement_fact_id = replacement_idx.is_a?(Integer) ? inserted_ids[replacement_idx] : nil

          begin
            fact = AdventureNarrativeFact
              .where(adventure_id: @adventure.id)
              .find_by(id: fact_id.to_i)
            unless fact
              @log.report_error(
                ArgumentError.new("Loremaster tried to invalidate unknown/foreign fact_id=#{fact_id}"),
                context: error_context.merge(source: "apply_results.invalidate_fact",
                                             fact_id: fact_id)
              )
              next
            end

            fact.update!(
              invalidated_at_loop_id: @loop&.id,
              invalidated_by_fact_id: replacement_fact_id,
            )
            invalidated_ids << fact.id
            @log.play_log!(
              "narrative_fact_invalidated",
              "#{@source}: invalidated fact ##{fact.id}" \
              "#{replacement_fact_id ? " (replaced by ##{replacement_fact_id})" : " (no replacement)"}",
              parsed_response: {
                fact_id: fact.id,
                replacement_fact_id: replacement_fact_id,
                replacement_source_idx: replacement_idx,
                reason: entry["reason"] || entry[:reason],
              },
            )
          rescue StandardError => e
            @log.report_error(
              e,
              context: error_context.merge(source: "apply_results.invalidate_fact",
                                           fact_id: fact_id,
                                           replacement_source_idx: replacement_idx)
            )
          end
        end

        invalidated_ids
      end

      def string_field(hash, key)
        v = hash[key] || hash[key.to_sym]
        v.is_a?(String) ? v : v.to_s
      end

      def error_context
        {
          step: "loremaster",
          adventure_id: @adventure&.id,
          loop_id: @loop&.id,
          source: @source,
        }
      end
    end
  end
end
