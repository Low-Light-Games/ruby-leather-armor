# frozen_string_literal: true

module Lore
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
