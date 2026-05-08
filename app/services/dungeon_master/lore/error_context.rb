# frozen_string_literal: true

module DungeonMaster
  module Lore
    # TODO: Improve readability — replace the kwargs bag (#with(**extra)) with a Struct so the supported key set is enforced rather than documented.
    class ErrorContext
      def initialize(step:, adventure_id:, loop_id:, source:)
        @base = {
          step:         step,
          adventure_id: adventure_id,
          loop_id:      loop_id,
          source:       source,
        }.freeze
      end

      def with(**extra)
        @base.merge(extra)
      end

      def to_h
        @base.dup
      end
    end
  end
end
