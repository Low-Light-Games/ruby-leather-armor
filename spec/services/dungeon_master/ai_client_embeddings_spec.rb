# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::AiClient, "#embeddings" do
  let(:config) do
    double(
      "DmConfig",
      model: "gpt-4o-mini",
      temperature: 0.8,
    )
  end
  let(:client) { described_class.new(config) }
  let(:openai_double) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_double)
  end

  def stub_success(vectors)
    data = vectors.each_with_index.map { |vec, i| { "embedding" => vec, "index" => i } }
    allow(openai_double).to receive(:embeddings).and_return({ "data" => data })
  end

  let(:small) { "text-embedding-3-small" }
  let(:large) { "text-embedding-3-large" }

  it "returns vectors in input order for a batch of texts" do
    vectors = [
      Array.new(3) { 0.1 },
      Array.new(3) { 0.2 },
      Array.new(3) { 0.3 },
    ]
    stub_success(vectors)

    result = client.embeddings(texts: ["first", "second", "third"], model: small)

    expect(result).to eq(vectors)
  end

  it "sends a single HTTP request for N texts (batched, not per-text)" do
    stub_success([[0.0], [0.0], [0.0], [0.0]])

    client.embeddings(texts: ["a", "b", "c", "d"], model: small)

    expect(openai_double).to have_received(:embeddings).once
  end

  it "accepts a 1-element array for single-query retrieval" do
    stub_success([[1.0, 0.0]])

    result = client.embeddings(texts: ["just one"], model: small)

    expect(result).to eq([[1.0, 0.0]])
  end

  it "passes the model and input through to OpenAI::Client#embeddings" do
    stub_success([[0.0]])

    client.embeddings(texts: ["x"], model: large)

    expect(openai_double).to have_received(:embeddings).with(
      parameters: { model: large, input: ["x"] },
    )
  end

  it "raises ArgumentError when model: is omitted (no hardcoded default)" do
    expect {
      client.embeddings(texts: ["x"])
    }.to raise_error(ArgumentError, /missing keyword: :?model/)
  end

  it "passes dimensions through when provided (for -3-large truncation)" do
    stub_success([[0.0]])

    client.embeddings(texts: ["x"], model: large, dimensions: 1536)

    expect(openai_double).to have_received(:embeddings).with(
      parameters: { model: large, input: ["x"], dimensions: 1536 },
    )
  end

  it "omits the dimensions parameter when not provided" do
    stub_success([[0.0]])

    client.embeddings(texts: ["x"], model: small)

    expect(openai_double).to have_received(:embeddings) do |args|
      expect(args[:parameters]).not_to have_key(:dimensions)
    end
  end

  it "re-orders out-of-order responses by the `index` key" do
    out_of_order = {
      "data" => [
        { "embedding" => [2.0], "index" => 1 },
        { "embedding" => [0.0], "index" => 0 },
        { "embedding" => [1.0], "index" => 2 },
      ],
    }
    allow(openai_double).to receive(:embeddings).and_return(out_of_order)

    result = client.embeddings(texts: %w[a b c], model: small)

    # Index 0 ~ "a", index 1 ~ "b", index 2 ~ "c".
    expect(result).to eq([[0.0], [2.0], [1.0]])
  end

  it "raises AiError on an empty texts array without hitting OpenAI" do
    expect(openai_double).not_to receive(:embeddings)

    expect { client.embeddings(texts: [], model: small) }.to raise_error(DungeonMaster::AiError)
  end

  it "retries on a transient Faraday::ConnectionFailed then succeeds" do
    call_count = 0
    allow(openai_double).to receive(:embeddings) do
      call_count += 1
      if call_count == 1
        raise Faraday::ConnectionFailed.new("boom")
      else
        { "data" => [{ "embedding" => [0.42], "index" => 0 }] }
      end
    end
    allow(client).to receive(:sleep)

    result = client.embeddings(texts: ["x"], model: small)

    expect(result).to eq([[0.42]])
    expect(call_count).to eq(2)
  end

  it "raises AiError after MAX_RETRIES transient failures" do
    allow(openai_double).to receive(:embeddings).and_raise(Faraday::ConnectionFailed.new("still boom"))
    allow(client).to receive(:sleep)

    expect { client.embeddings(texts: ["x"], model: small) }.to raise_error(DungeonMaster::AiError, /Could not reach the AI embeddings service/)
  end

  it "raises AiError when the response shape does not match the input count" do
    stub_success([[0.0]])

    expect {
      client.embeddings(texts: %w[first second], model: small)
    }.to raise_error(DungeonMaster::AiError, /Unexpected embeddings response shape/)
  end

  it "raises AiError when OpenAI returns an error body" do
    allow(openai_double).to receive(:embeddings).and_return(
      { "error" => { "message" => "model not found" } },
    )

    expect {
      client.embeddings(texts: ["x"], model: small)
    }.to raise_error(DungeonMaster::AiError, /model not found/)
  end
end
