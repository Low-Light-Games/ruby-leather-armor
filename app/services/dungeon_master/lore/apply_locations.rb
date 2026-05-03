# frozen_string_literal: true

module DungeonMaster
  module Lore
    class ApplyLocations
      def self.call(adventure:, log:, ai:, location_records:, source:)
        new(adventure: adventure, log: log, ai: ai,
            location_records: location_records, source: source).call
      end

      def initialize(adventure:, log:, ai:, location_records:, source:)
        @adventure        = adventure
        @log              = log
        @ai               = ai
        @location_records = location_records
        @source           = source
      end

      def call
        return [] if @location_records.empty?

        embeddings_by_idx = embed_records(@location_records)
        insert_records(@location_records, embeddings_by_idx)
      end

      private

      def embed_records(records)
        texts = records.map(&:embedding_text)
        vectors = embed_with_logging(texts)
        vectors.each_with_index.each_with_object({}) { |(vec, idx), acc| acc[idx] = vec }
      end

      def embed_with_logging(texts)
        @log.timed_embedding_call(
          "ApplyLocations — #{texts.length} location text(s)",
          model_used: embedding_model,
          source:     @source,
          ai:         @ai,
        ) do
          @ai.embeddings(**embeddings_kwargs(texts))
        end
      rescue DungeonMaster::AiError => e
        @log.report_error(e, context: error_context.with(source: "apply_locations.embeddings"))
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

      def insert_records(records, embeddings_by_idx)
        inserted = []

        records.each_with_index do |record, idx|
          begin
            row = AdventureLocation.create!(
              adventure_id:      @adventure.id,
              story_location_id: record.story_location_id,
              name:              record.name,
              description:       record.description,
              x:                 record.x,
              y:                 record.y,
              source:            @source,
              embedding:         embeddings_by_idx[idx],
            )
            inserted << row
            log_stored(row, record)
          rescue ActiveRecord::RecordNotUnique
            existing = AdventureLocation.find_by(
              adventure_id: @adventure.id,
              name:         record.name,
              source:       @source,
            )
            inserted << existing if existing
          rescue StandardError => e
            @log.report_error(
              e,
              context: error_context.with(
                source:       "apply_locations.insert_record",
                source_idx:   idx,
                name_preview: record.name.first(80),
              )
            )
          end
        end

        inserted
      end

      def log_stored(row, record)
        @log.play_log!(
          "adventure_location_stored",
          "#{@source}: stored location ##{row.id} (#{record.name})",
          parsed_response: {
            location_id: row.id,
            name:        record.name,
            x:           record.x,
            y:           record.y,
            source:      @source,
          },
        )
      end

      def error_context
        @error_context ||= ErrorContext.new(
          step:         "apply_locations",
          adventure_id: @adventure&.id,
          loop_id:      nil,
          source:       @source,
        )
      end
    end
  end
end
