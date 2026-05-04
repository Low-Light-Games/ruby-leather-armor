# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::EmbeddingCache do
  subject(:cache) { described_class.new }

  let(:vector_a) { Array.new(4, 0.1) }
  let(:vector_b) { Array.new(4, 0.2) }

  describe '#has? / #get / #store' do
    it 'is empty by default and becomes hot after store' do
      expect(cache.has?(text: 'hello', model: 'm')).to be false
      cache.store(text: 'hello', model: 'm', vector: vector_a)
      expect(cache.has?(text: 'hello', model: 'm')).to be true
      expect(cache.get(text: 'hello', model: 'm')).to eq(vector_a)
    end

    it 'distinguishes entries by text, model, and dimensions' do
      cache.store(text: 'a', model: 'm1', vector: vector_a)
      cache.store(text: 'a', model: 'm2', vector: vector_b)
      cache.store(text: 'a', model: 'm1', dimensions: 1536, vector: vector_b)

      expect(cache.get(text: 'a', model: 'm1')).to eq(vector_a)
      expect(cache.get(text: 'a', model: 'm2')).to eq(vector_b)
      expect(cache.get(text: 'a', model: 'm1', dimensions: 1536)).to eq(vector_b)
    end

    it 'ignores nil vectors' do
      cache.store(text: 'a', model: 'm', vector: nil)
      expect(cache.has?(text: 'a', model: 'm')).to be false
    end
  end

  describe '#warm!' do
    let(:ai)  { instance_double(DungeonMaster::AiClient) }
    let(:log) do
      double('Logging').tap do |l|
        allow(l).to receive(:timed_embedding_call) { |*_args, **_kw, &block| block.call }
      end
    end

    it 'batches uncached texts into one embeddings call and stores results' do
      expect(ai).to receive(:embeddings)
        .with(texts: %w[alpha beta], model: 'm')
        .once
        .and_return([vector_a, vector_b])

      cache.warm!(texts: %w[alpha beta], model: 'm', ai: ai, log: log, source: 'test')

      expect(cache.get(text: 'alpha', model: 'm')).to eq(vector_a)
      expect(cache.get(text: 'beta',  model: 'm')).to eq(vector_b)
    end

    it 'skips texts already in the cache and dedupes within the batch' do
      cache.store(text: 'alpha', model: 'm', vector: vector_a)

      expect(ai).to receive(:embeddings)
        .with(texts: %w[beta], model: 'm')
        .once
        .and_return([vector_b])

      cache.warm!(
        texts: ['alpha', 'beta', 'beta', '', nil],
        model: 'm', ai: ai, log: log, source: 'test',
      )

      expect(cache.get(text: 'beta', model: 'm')).to eq(vector_b)
    end

    it 'is a no-op when all texts are already cached' do
      cache.store(text: 'alpha', model: 'm', vector: vector_a)
      expect(ai).not_to receive(:embeddings)

      cache.warm!(texts: ['alpha'], model: 'm', ai: ai, log: log, source: 'test')
    end

    it 'logs a summary that includes truncated previews of every text in the batch' do
      captured_summary = nil
      allow(log).to receive(:timed_embedding_call) do |summary, **_kw, &block|
        captured_summary = summary
        block.call
      end
      allow(ai).to receive(:embeddings).and_return([vector_a, vector_b])

      cache.warm!(
        texts: ['look at the door', 'shove the orc'],
        model: 'm', ai: ai, log: log, source: 'scene_retrieval_prewarm',
      )

      expect(captured_summary).to include('scene_retrieval_prewarm batch [2]')
      expect(captured_summary).to include('look at the door')
      expect(captured_summary).to include('shove the orc')
    end

    it 'forwards the dimensions option to the embeddings call and the cache key' do
      expect(ai).to receive(:embeddings)
        .with(texts: %w[alpha], model: 'm', dimensions: 1536)
        .once
        .and_return([vector_a])

      cache.warm!(texts: %w[alpha], model: 'm', dimensions: 1536,
                  ai: ai, log: log, source: 'test')

      expect(cache.has?(text: 'alpha', model: 'm', dimensions: 1536)).to be true
      expect(cache.has?(text: 'alpha', model: 'm')).to be false
    end
  end
end
