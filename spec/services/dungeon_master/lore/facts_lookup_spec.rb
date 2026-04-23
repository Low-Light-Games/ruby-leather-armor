# frozen_string_literal: true

require "rails_helper"

# C9 of the narrative facts plan — read-side retrieval service.
#
# Verifies:
#   * Adventure scoping — facts from other adventures are never returned.
#   * Active-only filter — invalidated facts are excluded.
#   * `limit` is honored; defaults to DmConfig#narrative_facts_top_k.
#   * Returns [{fact_id:, text:, kind:, polarity:, distance:}, ...].
#   * Emits one `narrative_facts_retrieved` play_log event per call.
#   * One batched embeddings call (texts=[query], model=text-embedding-3-small).
#   * AiLog row written with `call_type: "embedding"` — read-side owner.
RSpec.describe DungeonMaster::Lore::FactsLookup do
  around do |ex|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ex.run
    ActiveJob::Base.queue_adapter = original
  end

  let(:adventure)       { create(:adventure) }
  let(:other_adventure) { create(:adventure) }
  let(:user)            { adventure.user }
  let(:log) { DungeonMaster::Logging.new(adventure: adventure, user: user, dm_service: "standard") }
  let(:ai)  { instance_double(DungeonMaster::AiClient) }

  # Dimension-1-dominant 1536-vectors: lets us nudge cosine similarity
  # deterministically by varying the first coordinate.
  def vec(v0)
    Array.new(1536) { |i| i.zero? ? v0.to_f : 0.0 }
  end

  def create_fact(adv:, text:, v0:, invalidated: false, kind: "state")
    fact = AdventureNarrativeFact.create!(
      adventure:  adv,
      text:       text,
      kind:       kind,
      polarity:   "asserts",
      source:     "seed",
      embedding:  vec(v0),
    )
    fact.update!(invalidated_at_loop_id: create_loop(adv).id) if invalidated
    fact
  end

  def create_loop(adv)
    AdventureLoop.create!(adventure: adv, registry_entry_uuid: SecureRandom.uuid, sequence_index: 0)
  end

  before do
    allow(ai).to receive(:embeddings).and_return([vec(1.0)])
    allow(ai).to receive(:last_usage).and_return(nil)
  end

  describe ".call" do
    it "returns empty and makes no embeddings call when the query is blank" do
      result = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "   ")
      expect(result).to eq([])
      expect(ai).not_to have_received(:embeddings)
    end

    it "returns hits scoped to the adventure only" do
      create_fact(adv: adventure,       text: "ocean state",          v0: 0.99)
      create_fact(adv: other_adventure, text: "other-advent ocean",   v0: 0.99)

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig in the sand")

      expect(hits.map { |h| h[:text] }).to eq(["ocean state"])
    end

    it "excludes invalidated facts" do
      create_fact(adv: adventure, text: "ocean state (old)", v0: 0.99, invalidated: true)
      create_fact(adv: adventure, text: "ocean state (new)", v0: 0.90)

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig in the sand")

      expect(hits.map { |h| h[:text] }).to eq(["ocean state (new)"])
    end

    it "honors an explicit limit" do
      3.times { |i| create_fact(adv: adventure, text: "fact #{i}", v0: 0.9 - (i * 0.1)) }

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "anything", limit: 2)

      expect(hits.length).to eq(2)
    end

    it "defaults limit from DmConfig#narrative_facts_top_k" do
      # DmConfig.instance returns a fresh AR load each call (first_or_create!),
      # so stub the class method to pin the same instance for the service.
      pinned = DmConfig.instance
      pinned.set("narrative_facts_top_k", 3)
      allow(DmConfig).to receive(:instance).and_return(pinned)

      5.times { |i| create_fact(adv: adventure, text: "fact #{i}", v0: 0.9 - (i * 0.1)) }

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "anything")

      expect(hits.length).to eq(3)
    end

    it "returns the canonical hit shape" do
      fact = create_fact(adv: adventure, text: "ocean state", v0: 0.99, kind: "state")

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig in the sand")

      expect(hits.first).to include(
        fact_id:  fact.id,
        text:     "ocean state",
        kind:     "state",
        polarity: "asserts",
      )
      expect(hits.first[:distance]).to be_a(Numeric)
    end

    it "makes exactly one batched embeddings call with texts=[query] and the embedding model" do
      create_fact(adv: adventure, text: "ocean state", v0: 0.99)

      described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig")

      expect(ai).to have_received(:embeddings).once
        .with(texts: ["dig"], model: "text-embedding-3-small")
    end

    it "uses the model configured on DmConfig and passes dimensions override when the model requires it" do
      pinned = DmConfig.instance
      pinned.set("narrative_facts_embedding_model", "text-embedding-3-large")
      allow(DmConfig).to receive(:instance).and_return(pinned)
      create_fact(adv: adventure, text: "ocean state", v0: 0.99)

      described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig")

      expect(ai).to have_received(:embeddings).with(
        texts: ["dig"],
        model: "text-embedding-3-large",
        dimensions: 1536,
      )
    end

    it "writes the read-side AiLog row with call_type: 'embedding'" do
      create_fact(adv: adventure, text: "ocean state", v0: 0.99)

      expect(log).to receive(:ai_log!).with(
        "embedding",
        a_string_including("FactsLookup query"),
        nil,
        hash_including(text_count: 1, dim: 1536, source: "facts_lookup"),
        hash_including(parse_status: "success", model_used: "text-embedding-3-small"),
      )
      allow(log).to receive(:play_log!)

      described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig")
    end

    it "emits a narrative_facts_retrieved play_log event with the hit summary" do
      create_fact(adv: adventure, text: "ocean state", v0: 0.99)

      expect(log).to receive(:play_log!).with(
        "narrative_facts_retrieved",
        a_string_including("retrieved 1 fact"),
        hash_including(parsed_response: hash_including(:query_preview, :limit, :hits)),
      )
      allow(log).to receive(:ai_log!)

      described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig")
    end

    it "reports to Sentry and returns [] when the embeddings call raises" do
      allow(ai).to receive(:embeddings).and_raise(DungeonMaster::AiError, "upstream down")
      reports = []
      allow(log).to receive(:report_error).and_wrap_original do |orig, exception, **kwargs|
        reports << { exception: exception, kwargs: kwargs }
        orig.call(exception, **kwargs)
      end
      allow(log).to receive(:ai_log_error!)

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig")

      expect(hits).to eq([])
      expect(reports.any? { |r| r[:kwargs].dig(:context, :step) == "facts_lookup" }).to be(true),
        "expected log.report_error with step: 'facts_lookup' but saw: #{reports.map { _1[:kwargs] }}"
    end
  end

  describe "ordering" do
    it "orders hits by cosine distance (closest first)" do
      # Query will embed to vec(1.0). Create two facts with clear ordering.
      far  = create_fact(adv: adventure, text: "far fact",  v0: -1.0)
      near = create_fact(adv: adventure, text: "near fact", v0:  1.0)

      hits = described_class.call(adventure: adventure, ai: ai, log: log, query_text: "dig", limit: 2)

      expect(hits.map { |h| h[:fact_id] }).to eq([near.id, far.id])
    end
  end
end
