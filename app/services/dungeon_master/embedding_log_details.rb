# frozen_string_literal: true

module DungeonMaster
  # `ai_log!`'s `parsed_response:` payload for the `"embedding"` call
  # type. Lives at the DM top level (not under `Lore::`) because the
  # shape is part of the logging protocol — it's what every writer of
  # an "embedding" AiLog row must conform to. Built by
  # `Logging#timed_embedding_call` on the success path; callers only
  # supply the `source:` tag that names them (e.g. "loremaster",
  # "seed", "facts_lookup").
  #
  # Shape (persisted as JSON in PlayLog#parsed_response):
  #   text_count — Integer, number of texts in the batch.
  #   dim        — Integer or nil, length of the returned vectors.
  #   source     — String, caller tag.
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
