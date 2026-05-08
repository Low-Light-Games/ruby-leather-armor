# frozen_string_literal: true

module Combat
  module Resolvers
    class MovePlan
      attr_reader :origin, :target_x, :target_y, :distance, :delta, :mode, :aoo_outcomes

      # @param origin [Combat::Position]
      # @param destination [Hash{x: Integer, y: Integer}]
      # @param movement [Hash{distance: Integer, delta: Hash, mode: String}]
      # @param aoo_outcomes [Array<Combat::NpcAttackOutcome>]
      def initialize(origin:, destination:, movement:, aoo_outcomes:)
        @origin = origin
        @target_x = destination[:x]
        @target_y = destination[:y]
        @distance = movement[:distance]
        @delta = movement[:delta]
        @mode = movement[:mode]
        @aoo_outcomes = aoo_outcomes
      end

      def destination
        { x: target_x, y: target_y }
      end

      def economy_label
        "#{mode} (#{distance} squares)"
      end
    end
  end
end
