# frozen_string_literal: true

module Ai
  class EmbeddingCache
    def initialize
      @store = {}
    end

    def has?(text:, model:, dimensions: nil)
      @store.key?(key_for(text, model, dimensions))
    end

    def get(text:, model:, dimensions: nil)
      @store[key_for(text, model, dimensions)]
    end

    def store(text:, model:, dimensions: nil, vector:)
      return if vector.nil?

      @store[key_for(text, model, dimensions)] = vector
    end

    def warm!(texts:, model:, ai:, log:, source:, dimensions: nil)
      missing = Array(texts).map(&:to_s).reject(&:empty?).uniq.reject do |t|
        has?(text: t, model: model, dimensions: dimensions)
      end
      return if missing.empty?

      vectors = log.timed_embedding_call(
        batch_summary(source, missing),
        model_used: model,
        source:     source,
        ai:         ai,
      ) do
        kwargs = { texts: missing, model: model }
        kwargs[:dimensions] = dimensions if dimensions
        ai.embeddings(**kwargs)
      end

      missing.zip(vectors).each do |text, vector|
        store(text: text, model: model, dimensions: dimensions, vector: vector)
      end
    rescue StandardError => e
      log.report_error(e, context: { source: "embedding_cache.warm!", warm_source: source })
      nil
    end

    private

    def batch_summary(source, texts)
      previews = texts.map { |t| t.truncate(60) }.join(' | ')
      "#{source} batch [#{texts.length}] — #{previews}".truncate(280)
    end

    def key_for(text, model, dimensions)
      [text.to_s, model.to_s, dimensions]
    end
  end
end
