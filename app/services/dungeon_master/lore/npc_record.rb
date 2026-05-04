# frozen_string_literal: true

module DungeonMaster
  module Lore
    class NpcRecord
      attr_reader :name, :description, :attitude, :location_name, :story_npc_id

      def initialize(name:, description: "", attitude: "indifferent",
                     location_name: nil, story_npc_id: nil)
        @name          = name.to_s.strip
        @description   = description.to_s
        @attitude      = attitude.to_s.presence || "indifferent"
        @location_name = location_name&.to_s.presence
        @story_npc_id  = story_npc_id
      end

      def embedding_text
        parts = [@name]
        parts << "(#{@attitude})" if @attitude.present?
        parts << @description if @description.present?
        parts.reject(&:empty?).join(" — ")
      end

      def to_h
        {
          name:          @name,
          description:   @description,
          attitude:      @attitude,
          location_name: @location_name,
          story_npc_id:  @story_npc_id,
        }
      end

      def self.from_story_npc(story_npc)
        new(
          name:          story_npc.name,
          description:   story_npc.description.to_s,
          attitude:      story_npc.attitude,
          location_name: story_npc.location&.name,
          story_npc_id:  story_npc.id,
        )
      end
    end
  end
end
