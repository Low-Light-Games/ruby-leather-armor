# frozen_string_literal: true

module DungeonMaster
  module SceneRetrieval
    # TODO: Improve readability — value object whose attr_reader list already encodes the shape; the prose preamble is redundant.
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
