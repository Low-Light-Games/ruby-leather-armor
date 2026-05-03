# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Sole writer of `adventure_npcs`. Mirrors `Lore::ApplyResults`'s
    # error contract: embedding failures raise (with Sentry), per-row
    # insert failures notify Sentry but continue (lossy-with-Sentry per
    # §8). Idempotent reapply is guarded by the partial unique index on
    # `(adventure_id, name) WHERE source = 'seed'` — a duplicate seed
    # write resolves to the existing row rather than raising.
    #
    # Inputs are plain Ruby hashes shaped like:
    #   { name:, description:, attitude:, location_name:, story_npc_id: }
    # Caller is responsible for mapping any source data (e.g. StoryNpc)
    # into that hash.
    class ApplyNpcs
      def self.call(adventure:, log:, ai:, npc_records:, source:)
        new(adventure: adventure, log: log, ai: ai,
            npc_records: npc_records, source: source).call
      end

      def initialize(adventure:, log:, ai:, npc_records:, source:)
        @adventure   = adventure
        @log         = log
        @ai          = ai
        @npc_records = Array(npc_records).select { |r| r.is_a?(Hash) }
        @source      = source
      end

      def call
        return [] if @npc_records.empty?

        embeddings_by_idx = embed_npcs(@npc_records)
        insert_npcs(@npc_records, embeddings_by_idx)
      end

      private

      def embed_npcs(records)
        texts = records.map { |r| embedding_text_for(r) }

        if texts.any?(&:empty?)
          @log.report_error(
            ArgumentError.new("ApplyNpcs received an NPC record with empty embedding text"),
            context: error_context.with(texts_preview: texts.first(3))
          )
        end

        vectors = embed_with_logging(texts)
        vectors.each_with_index.each_with_object({}) { |(vec, idx), acc| acc[idx] = vec }
      end

      def embedding_text_for(record)
        name        = record[:name].to_s.strip
        attitude    = record[:attitude].to_s.strip.presence || "indifferent"
        description = record[:description].to_s.strip
        parts = [name]
        parts << "(#{attitude})" if attitude.present?
        parts << description if description.present?
        parts.reject(&:empty?).join(" — ")
      end

      def embed_with_logging(texts)
        @log.timed_embedding_call(
          "ApplyNpcs — #{texts.length} NPC text(s)",
          model_used: embedding_model,
          source:     @source,
          ai:         @ai,
        ) do
          @ai.embeddings(**embeddings_kwargs(texts))
        end
      rescue DungeonMaster::AiError => e
        @log.report_error(e, context: error_context.with(source: "apply_npcs.embeddings"))
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

      def insert_npcs(records, embeddings_by_idx)
        inserted = []

        records.each_with_index do |record, idx|
          name          = record[:name].to_s.strip
          description   = record[:description].to_s
          attitude      = record[:attitude].to_s.presence || "indifferent"
          location_name = record[:location_name].to_s.presence
          story_npc_id  = record[:story_npc_id]
          embedding     = embeddings_by_idx[idx]

          begin
            row = AdventureNpc.create!(
              adventure_id:  @adventure.id,
              story_npc_id:  story_npc_id,
              name:          name,
              description:   description,
              attitude:      attitude,
              location_name: location_name,
              source:        @source,
              embedding:     embedding,
            )
            inserted << row
            @log.play_log!(
              "adventure_npc_stored",
              "#{@source}: stored NPC ##{row.id} (#{name})",
              parsed_response: {
                npc_id:        row.id,
                name:          name,
                attitude:      attitude,
                location_name: location_name,
                source:        @source,
              },
            )
          rescue ActiveRecord::RecordNotUnique
            existing = AdventureNpc.find_by(
              adventure_id: @adventure.id,
              name:         name,
              source:       @source,
            )
            inserted << existing if existing
          rescue StandardError => e
            @log.report_error(
              e,
              context: error_context.with(
                source:        "apply_npcs.insert_npc",
                source_idx:    idx,
                name_preview:  name.first(80),
                location_name: location_name,
              )
            )
          end
        end

        inserted
      end

      def error_context
        @error_context ||= ErrorContext.new(
          step:         "apply_npcs",
          adventure_id: @adventure&.id,
          loop_id:      nil,
          source:       @source,
        )
      end
    end
  end
end
