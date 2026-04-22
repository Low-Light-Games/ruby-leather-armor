# frozen_string_literal: true

module DungeonMaster
  module Lore
    # The net change to `adventure_narrative_facts` produced by a single
    # run of `Lore::ApplyResults` — what rows were inserted, and what
    # previously-stored rows were flagged invalidated. Returned to the
    # caller purely for observability; Stagehand does not branch on its
    # contents. See docs/pipeline_steps.md Decision 37.
    class FactsChangeSet
      attr_reader :inserted_fact_ids, :invalidated_fact_ids

      def initialize(inserted_fact_ids: [], invalidated_fact_ids: [])
        @inserted_fact_ids    = Array(inserted_fact_ids).freeze
        @invalidated_fact_ids = Array(invalidated_fact_ids).freeze
      end

      def self.empty
        new
      end

      def to_h
        { inserted_fact_ids: @inserted_fact_ids, invalidated_fact_ids: @invalidated_fact_ids }
      end
    end
  end
end
