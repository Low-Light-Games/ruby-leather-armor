# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Sole writer of `adventure_narrative_facts`. Contract, call sites, and
    # lossy-with-Sentry rationale live in docs/pipeline_steps.md Decision 37
    # and docs/design_philosophy.md §18.
    class ApplyResults
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
        return FactsChangeSet.empty if nothing_to_apply?

        embeddings_by_idx = embed_facts(facts)
        inserted_ids = insert_facts(facts, embeddings_by_idx)
        invalidated_ids = apply_invalidations(invalidates, inserted_ids)

        FactsChangeSet.new(
          inserted_fact_ids:    inserted_ids.values.compact,
          invalidated_fact_ids: invalidated_ids,
        )
      end

      private

      def nothing_to_apply?
        facts.empty? && invalidates.empty?
      end

      def facts
        @facts ||= Array(@result["facts"] || @result[:facts]).select { |f| f.is_a?(Hash) }
      end

      def invalidates
        @invalidates ||= Array(@result["invalidates"] || @result[:invalidates]).select { |i| i.is_a?(Hash) }
      end

      def embed_facts(facts)
        return {} if facts.empty?

        texts = facts.map { |f| TextNormalizer.indifferent_string(f, "text") }

        if texts.any?(&:empty?)
          @log.report_error(
            ArgumentError.new("Loremaster emitted a fact with empty text"),
            context: error_context.with(texts_preview: texts.first(3))
          )
        end

        vectors = embed_with_logging(texts)
        vectors.each_with_index.each_with_object({}) { |(vec, idx), acc| acc[idx] = vec }
      end

      def embed_with_logging(texts)
        @log.timed_embedding_call(
          "Loremaster apply — #{texts.length} fact text(s)",
          model_used: embedding_model,
          source:     @source,
        ) do
          @ai.embeddings(**embeddings_kwargs(texts))
        end
      rescue DungeonMaster::AiError => e
        @log.report_error(e, context: error_context.with(source: "apply_results.embeddings"))
        raise
      end

      def embeddings_kwargs(texts)
        kwargs = { texts: texts, model: embedding_model }
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

      def insert_facts(facts, embeddings_by_idx)
        inserted_ids = {}

        facts.each_with_index do |fact, idx|
          text = TextNormalizer.indifferent_string(fact, "text")
          kind = TextNormalizer.indifferent_string(fact, "kind")
          polarity = TextNormalizer.indifferent_string(fact, "polarity").presence || "asserts"
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
              parsed_response: PlayLogEvents::StoredFact.new(
                fact_id:    row.id,
                kind:       kind,
                polarity:   polarity,
                source:     @source,
                source_idx: idx,
                text:       text,
              ).to_h,
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
              context: error_context.with(
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
            fact = AdventureNarrativeFact.for_adventure(@adventure).find_by(id: fact_id.to_i)
            unless fact
              @log.report_error(
                ArgumentError.new("Loremaster tried to invalidate unknown/foreign fact_id=#{fact_id}"),
                context: error_context.with(source: "apply_results.invalidate_fact", fact_id: fact_id)
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
              parsed_response: PlayLogEvents::InvalidatedFact.new(
                fact_id:                fact.id,
                replacement_fact_id:    replacement_fact_id,
                replacement_source_idx: replacement_idx,
                reason:                 entry["reason"] || entry[:reason],
              ).to_h,
            )
          rescue StandardError => e
            @log.report_error(
              e,
              context: error_context.with(
                source: "apply_results.invalidate_fact",
                fact_id: fact_id,
                replacement_source_idx: replacement_idx,
              )
            )
          end
        end

        invalidated_ids
      end

      def error_context
        @error_context ||= ErrorContext.new(
          step:         "loremaster",
          adventure_id: @adventure&.id,
          loop_id:      @loop&.id,
          source:       @source,
        )
      end
    end
  end
end
