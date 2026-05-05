# frozen_string_literal: true

module DungeonMaster
  module SceneRetrieval
    class ForResolution
      DEFAULT_LOCATION_LIMIT = 4
      DEFAULT_NPC_LIMIT      = 4

      def self.call(adventure:, intent_text:, ai:, log:,
                    fact_limit: nil,
                    location_limit: DEFAULT_LOCATION_LIMIT,
                    npc_limit: DEFAULT_NPC_LIMIT)
        new(adventure: adventure, intent_text: intent_text, ai: ai, log: log,
            fact_limit: fact_limit, location_limit: location_limit, npc_limit: npc_limit).call
      end

      def initialize(adventure:, intent_text:, ai:, log:,
                     fact_limit:, location_limit:, npc_limit:)
        @adventure      = adventure
        @intent_text    = intent_text.to_s
        @ai             = ai
        @log            = log
        @fact_limit     = fact_limit
        @location_limit = location_limit
        @npc_limit      = npc_limit
      end

      def call
        prewarm_query_embeddings
        Retrieval.new(
          facts:     facts_lookup,
          locations: locations_with_relative_position,
          npcs:      npcs_lookup,
        )
      end

      private

      def prewarm_query_embeddings
        cache = @log.respond_to?(:embedding_cache) ? @log.embedding_cache : nil
        return unless cache

        texts = [
          @intent_text,
          SceneFacts::ForResolution.composed_query_text_for(
            adventure:   @adventure,
            intent_text: @intent_text,
          ),
        ]

        cache.warm!(
          texts:      texts,
          model:      DmConfig.instance.narrative_facts_embedding_model,
          dimensions: DmConfig.instance.narrative_facts_embedding_dimensions,
          ai:         @ai,
          log:        @log,
          source:     "scene_retrieval_prewarm",
        )
      end

      def facts_lookup
        SceneFacts::ForResolution.call(
          adventure:   @adventure, intent_text: @intent_text,
          ai:          @ai, log: @log, limit: @fact_limit,
        )
      end

      def locations_with_relative_position
        hits = Lore::LocationsLookup.call(
          adventure: @adventure, ai: @ai, log: @log,
          query_text: @intent_text, limit: @location_limit,
        )
        hits.map { |hit| hit.merge(annotated_position(hit)) }
      end

      def npcs_lookup
        Lore::NpcsLookup.call(
          adventure: @adventure, ai: @ai, log: @log,
          query_text: @intent_text, limit: @npc_limit,
        )
      end

      def annotated_position(hit)
        return { distance_miles: nil, bearing: nil } unless origin

        dx = hit[:x].to_f - origin.x.to_f
        dy = hit[:y].to_f - origin.y.to_f
        units = Math.sqrt((dx * dx) + (dy * dy))
        miles = units * @adventure.coordinate_scale.to_f

        {
          distance_miles: miles.round(2),
          bearing:        Bearing.label(dx: dx, dy: dy),
        }
      end

      def origin
        @origin ||= @adventure.current_location
      end
    end
  end
end
