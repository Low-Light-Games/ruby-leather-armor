# frozen_string_literal: true

module DungeonMaster
  module Lore
    class ApplyNpcs
      def self.call(adventure:, log:, ai:, npc_records:, source:)
        new(adventure: adventure, log: log, ai: ai,
            npc_records: npc_records, source: source).call
      end

      def initialize(adventure:, log:, ai:, npc_records:, source:)
        @adventure   = adventure
        @log         = log
        @ai          = ai
        @npc_records = npc_records
        @source      = source
      end

      def call
        return [] if @npc_records.empty?

        embeddings_by_index = embed_records_for_adventure(@npc_records)
        insert_records_into_adventure(@npc_records, embeddings_by_index)
      end

      private

      def embed_records_for_adventure(records)
        texts = records.map(&:embedding_text)
        vectors = embed_with_logging(texts)
        embeddings_by_record_index(vectors)
      end

      def embeddings_by_record_index(vectors)
        vectors.each_with_index.to_h { |vector, record_index| [record_index, vector] }
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
      rescue Ai::Error => e
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

      def insert_records_into_adventure(records, embeddings_by_index)
        inserted = []

        records.each_with_index do |record, record_index|
          begin
            row = AdventureNpc.create!(
              adventure_id:  @adventure.id,
              story_npc_id:  record.story_npc_id,
              name:          record.name,
              description:   record.description,
              attitude:      record.attitude,
              location_name: record.location_name,
              source:        @source,
              embedding:     embeddings_by_index[record_index],
            )
            inserted << row
            log_stored(row, record)
          rescue ActiveRecord::RecordNotUnique
            existing = AdventureNpc.find_by(
              adventure_id: @adventure.id,
              name:         record.name,
              source:       @source,
            )
            inserted << existing if existing
          rescue StandardError => e
            @log.report_error(
              e,
              context: error_context.with(
                source:        "apply_npcs.insert_record",
                source_idx:    record_index,
                name_preview:  record.name.first(80),
                location_name: record.location_name,
              )
            )
          end
        end

        inserted
      end

      def log_stored(row, record)
        @log.play_log!(
          "adventure_npc_stored",
          "#{@source}: stored NPC ##{row.id} (#{record.name})",
          parsed_response: {
            npc_id:        row.id,
            name:          record.name,
            attitude:      record.attitude,
            location_name: record.location_name,
            source:        @source,
          },
        )
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
