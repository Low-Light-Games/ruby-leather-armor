# frozen_string_literal: true

module Lore
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
