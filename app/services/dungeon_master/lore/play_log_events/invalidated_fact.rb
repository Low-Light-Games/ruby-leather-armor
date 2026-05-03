# frozen_string_literal: true

module DungeonMaster
  module Lore
    module PlayLogEvents
      class InvalidatedFact
        attr_reader :fact_id, :replacement_fact_id, :replacement_source_idx, :reason

        def initialize(fact_id:, replacement_fact_id:, replacement_source_idx:, reason:)
          @fact_id                = fact_id
          @replacement_fact_id    = replacement_fact_id
          @replacement_source_idx = replacement_source_idx
          @reason                 = reason
        end

        def to_h
          {
            fact_id:                @fact_id,
            replacement_fact_id:    @replacement_fact_id,
            replacement_source_idx: @replacement_source_idx,
            reason:                 @reason,
          }
        end
      end
    end
  end
end
