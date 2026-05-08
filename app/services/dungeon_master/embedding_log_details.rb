# frozen_string_literal: true

module DungeonMaster
  # TODO: Improve readability — value object whose attr_reader list already encodes the shape; the prose preamble is redundant.
  class EmbeddingLogDetails
    attr_reader :text_count, :dim, :source

    def initialize(text_count:, dim:, source:)
      @text_count = text_count
      @dim        = dim
      @source     = source
    end

    def self.from_vectors(vectors, source:)
      new(text_count: vectors.length, dim: vectors.first&.length, source: source)
    end

    def to_h
      { text_count: @text_count, dim: @dim, source: @source }
    end
  end
end
