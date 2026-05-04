# frozen_string_literal: true

module DungeonMaster
  module SceneRetrieval
    # Value object returned by `SceneRetrieval::ForResolution`. Carries
    # the three retrieval slices the GM-facing prompts consume:
    # established facts, nearby locations (with relative distance and
    # bearing), and known NPCs. Consumers (`partials/scene_retrieval`)
    # iterate via the readers; tests and Admin tooling read the hash form
    # via `#to_h`.
    class Retrieval
      attr_reader :facts, :locations, :npcs

      def initialize(facts:, locations:, npcs:)
        @facts     = Array(facts)
        @locations = Array(locations)
        @npcs      = Array(npcs)
      end

      def empty?
        @facts.empty? && @locations.empty? && @npcs.empty?
      end

      def to_h
        { facts: @facts, locations: @locations, npcs: @npcs }
      end
    end
  end
end
