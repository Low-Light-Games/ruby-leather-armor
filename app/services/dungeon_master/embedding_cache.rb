# frozen_string_literal: true

module DungeonMaster
  # Per-pipeline-execution memo for OpenAI embedding vectors.
  #
  # Lives on `Logging` so every step in one turn shares the same cache.
  # A typical turn issues retrieval calls from RollRequest, Mechanic, and
  # Stagehand — and the composer (`SceneRetrieval::ForResolution`) issues
  # three lookups whose query text usually only differs in the
  # facts-side composition. Without this, the same text gets re-embedded
  # 3–7 times per turn (~5s of serial latency on adv 170).
  #
  # Keyed by `[text, model, dimensions]`. Cache is in-memory only; it
  # never touches the DB and is discarded when the Logging instance
  # goes out of scope at the end of the pipeline run.
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

    # Batch-embed any uncached texts in one API call and stash the
    # resulting vectors. Caller passes `ai:` and `log:` so the batched
    # call still emits a normal `embedding` PlayLog entry (one row,
    # rather than N) for observability.
    #
    # Returns nothing useful; consumers go through `get`/`has?`.
    def warm!(texts:, model:, ai:, log:, source:, dimensions: nil)
      missing = Array(texts).map(&:to_s).reject(&:empty?).uniq.reject do |t|
        has?(text: t, model: model, dimensions: dimensions)
      end
      return if missing.empty?

      vectors = log.timed_embedding_call(
        "#{source} batch — #{missing.length} text(s)",
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
    end

    private

    def key_for(text, model, dimensions)
      [text.to_s, model.to_s, dimensions]
    end
  end
end
