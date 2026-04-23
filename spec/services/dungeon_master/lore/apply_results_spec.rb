# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Lore::ApplyResults do
  # Force the synchronous :test adapter so each play_log!/ai_log! call from
  # the service does not leave live :async worker threads dangling around
  # PlayLog rows that the transactional fixture is about to roll back.
  around do |ex|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ex.run
    ActiveJob::Base.queue_adapter = original
  end

  let(:adventure) { create(:adventure) }
  let(:user)      { adventure.user }
  let(:loop_row) do
    AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: SecureRandom.uuid,
      sequence_index: 0,
    )
  end
  let(:log) { DungeonMaster::Logging.new(adventure: adventure, user: user, dm_service: "standard") }
  let(:ai)  { instance_double(DungeonMaster::AiClient) }

  def vec(seed)
    Array.new(1536) { |i| i.zero? ? seed.to_f : 0.0 }
  end

  def stub_embeddings(_n)
    allow(ai).to receive(:embeddings) do |**kw|
      Array(kw[:texts]).each_with_index.map { |_, i| vec(i + 1) }
    end
  end

  describe ".call" do
    it "returns early with no embeddings call when result is empty" do
      allow(ai).to receive(:embeddings)

      outcome = described_class.call(
        adventure: adventure, loop: loop_row, log: log, ai: ai,
        result: { "facts" => [], "invalidates" => [] },
      )

      expect(ai).not_to have_received(:embeddings)
      expect(outcome.inserted_fact_ids).to eq([])
      expect(outcome.invalidated_fact_ids).to eq([])
    end

    it "issues one batched embeddings call for all fact texts, in order" do
      stub_embeddings(3)

      described_class.call(
        adventure: adventure, loop: loop_row, log: log, ai: ai,
        result: {
          "facts" => [
            { "text" => "A happened",          "kind" => "event",  "entities" => [], "polarity" => "asserts" },
            { "text" => "Player is in ocean",  "kind" => "state",  "entities" => ["player"], "polarity" => "asserts" },
            { "text" => "Gerta the innkeeper", "kind" => "entity", "entities" => ["Gerta"],  "polarity" => "asserts" },
          ],
          "invalidates" => [],
        },
      )

      expect(ai).to have_received(:embeddings).once.with(
        texts: ["A happened", "Player is in ocean", "Gerta the innkeeper"],
        model: "text-embedding-3-small",
      )
    end

    it "uses the model configured on DmConfig and passes dimensions override when the model requires it" do
      pinned = DmConfig.instance
      pinned.set("narrative_facts_embedding_model", "text-embedding-3-large")
      allow(DmConfig).to receive(:instance).and_return(pinned)
      stub_embeddings(1)

      described_class.call(
        adventure: adventure, loop: loop_row, log: log, ai: ai,
        result: {
          "facts" => [{ "text" => "x", "kind" => "event", "entities" => [], "polarity" => "asserts" }],
          "invalidates" => [],
        },
      )

      expect(ai).to have_received(:embeddings).with(
        texts: ["x"],
        model: "text-embedding-3-large",
        dimensions: 1536,
      )
    end

    it "inserts fact rows with kind, polarity, entities, source, source_idx, and loop id" do
      stub_embeddings(2)

      outcome = described_class.call(
        adventure: adventure, loop: loop_row, log: log, ai: ai,
        result: {
          "facts" => [
            { "text" => "E1", "kind" => "event", "entities" => ["Alice"],   "polarity" => "asserts" },
            { "text" => "S1", "kind" => "state", "entities" => ["weather"], "polarity" => "negates" },
          ],
          "invalidates" => [],
        },
      )

      rows = AdventureNarrativeFact.where(id: outcome.inserted_fact_ids).order(:source_idx)
      expect(rows.length).to eq(2)

      expect(rows.first).to have_attributes(
        adventure_id: adventure.id,
        text: "E1", kind: "event", polarity: "asserts", entities: ["Alice"],
        source: "loremaster", source_idx: 0,
        introduced_at_loop_id: loop_row.id,
      )
      expect(rows.first.embedding).to be_present
      expect(rows.last).to have_attributes(text: "S1", kind: "state",
                                            polarity: "negates", entities: ["weather"],
                                            source_idx: 1)
    end

    it "writes an 'embedding' AiLog row via log.ai_log! on success" do
      stub_embeddings(1)

      expect {
        described_class.call(
          adventure: adventure, loop: loop_row, log: log, ai: ai,
          result: { "facts" => [{ "text" => "x", "kind" => "event", "entities" => [], "polarity" => "asserts" }],
                    "invalidates" => [] },
        )
      }.to change { PlayLog.where(event_type: "embedding", adventure_id: adventure.id).count }.by(1)

      row = PlayLog.where(event_type: "embedding", adventure_id: adventure.id).last
      expect(row.status).to eq("success")
      expect(row.model_used).to eq("text-embedding-3-small")
    end

    it "writes an 'embedding' error AiLog and re-raises when the embeddings call raises AiError" do
      allow(ai).to receive(:embeddings).and_raise(DungeonMaster::AiError, "OpenAI is on fire")

      expect {
        described_class.call(
          adventure: adventure, loop: loop_row, log: log, ai: ai,
          result: { "facts" => [{ "text" => "x", "kind" => "event", "entities" => [], "polarity" => "asserts" }],
                    "invalidates" => [] },
        )
      }.to raise_error(DungeonMaster::AiError)

      expect(PlayLog.where(event_type: "embedding",
                           adventure_id: adventure.id,
                           status: "api_error").count).to eq(1)
    end

    it "reports a Sentry error via log.report_error before re-raising on embeddings failure" do
      allow(ai).to receive(:embeddings).and_raise(DungeonMaster::AiError, "boom")
      allow(log).to receive(:report_error).and_call_original

      expect {
        described_class.call(
          adventure: adventure, loop: loop_row, log: log, ai: ai,
          result: { "facts" => [{ "text" => "x", "kind" => "event", "entities" => [], "polarity" => "asserts" }],
                    "invalidates" => [] },
        )
      }.to raise_error(DungeonMaster::AiError)

      expect(log).to have_received(:report_error).with(
        instance_of(DungeonMaster::AiError),
        hash_including(context: hash_including(step: "loremaster",
                                                adventure_id: adventure.id,
                                                loop_id: loop_row.id,
                                                source: "apply_results.embeddings"))
      )
    end

    it "emits narrative_fact_stored play_log per inserted fact" do
      stub_embeddings(2)

      expect {
        described_class.call(
          adventure: adventure, loop: loop_row, log: log, ai: ai,
          result: {
            "facts" => [
              { "text" => "F1", "kind" => "event", "entities" => [], "polarity" => "asserts" },
              { "text" => "F2", "kind" => "entity", "entities" => [], "polarity" => "asserts" },
            ],
            "invalidates" => [],
          },
        )
      }.to change { PlayLog.where(event_type: "narrative_fact_stored", adventure_id: adventure.id).count }.by(2)
    end
  end

  describe "invalidations" do
    let!(:old_state) do
      AdventureNarrativeFact.create!(
        adventure: adventure, text: "Player is blinded", kind: "state",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 0,
        embedding: vec(99),
      )
    end
    let(:next_loop) do
      AdventureLoop.create!(
        adventure: adventure, registry_entry_uuid: SecureRandom.uuid, sequence_index: 1,
      )
    end

    it "sets invalidated_at_loop_id and invalidated_by_fact_id when replacement_source_idx is provided" do
      stub_embeddings(1)

      outcome = described_class.call(
        adventure: adventure, loop: next_loop, log: log, ai: ai,
        result: {
          "facts" => [
            { "text" => "Player can see again", "kind" => "state", "entities" => [], "polarity" => "asserts" },
          ],
          "invalidates" => [
            { "fact_id" => old_state.id, "reason" => "cleansed", "replacement_source_idx" => 0 },
          ],
        },
      )

      old_state.reload
      expect(old_state.invalidated_at_loop_id).to eq(next_loop.id)
      expect(old_state.invalidated_by_fact_id).to eq(outcome.inserted_fact_ids.first)
      expect(outcome.invalidated_fact_ids).to eq([old_state.id])
    end

    it "supports the null-replacement case (a state ended with no successor)" do
      stub_embeddings(0) # no new facts

      allow(ai).to receive(:embeddings)

      described_class.call(
        adventure: adventure, loop: next_loop, log: log, ai: ai,
        result: {
          "facts" => [],
          "invalidates" => [
            { "fact_id" => old_state.id, "reason" => "condition ended",
              "replacement_source_idx" => nil },
          ],
        },
      )

      old_state.reload
      expect(old_state.invalidated_at_loop_id).to eq(next_loop.id)
      expect(old_state.invalidated_by_fact_id).to be_nil
      expect(ai).not_to have_received(:embeddings)
    end

    it "supports cross-index invalidation (invalidate old idx 0, replace with new idx 2)" do
      stub_embeddings(3)

      outcome = described_class.call(
        adventure: adventure, loop: next_loop, log: log, ai: ai,
        result: {
          "facts" => [
            { "text" => "unrelated event 1", "kind" => "event",  "polarity" => "asserts" },
            { "text" => "unrelated event 2", "kind" => "event",  "polarity" => "asserts" },
            { "text" => "player is healed",  "kind" => "state",  "polarity" => "asserts" },
          ],
          "invalidates" => [
            { "fact_id" => old_state.id, "reason" => "cleric action",
              "replacement_source_idx" => 2 },
          ],
        },
      )

      old_state.reload
      replacement_id = outcome.inserted_fact_ids[2]
      expect(old_state.invalidated_by_fact_id).to eq(replacement_id)
    end

    it "reports and skips an invalidate entry that targets an unknown fact_id" do
      allow(ai).to receive(:embeddings).and_return([])
      allow(log).to receive(:report_error).and_call_original

      described_class.call(
        adventure: adventure, loop: next_loop, log: log, ai: ai,
        result: {
          "facts" => [],
          "invalidates" => [{ "fact_id" => 999_999, "reason" => "typo" }],
        },
      )

      old_state.reload
      expect(old_state.invalidated_at_loop_id).to be_nil
      expect(log).to have_received(:report_error).with(
        instance_of(ArgumentError),
        hash_including(context: hash_including(source: "apply_results.invalidate_fact",
                                                fact_id: 999_999))
      )
    end

    it "does not invalidate a fact that belongs to a different adventure" do
      other_adventure = create(:adventure)
      other_loop = AdventureLoop.create!(
        adventure: other_adventure, registry_entry_uuid: SecureRandom.uuid, sequence_index: 0,
      )
      foreign_fact = AdventureNarrativeFact.create!(
        adventure: other_adventure, text: "foreign", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: other_loop, source_idx: 0,
      )
      allow(ai).to receive(:embeddings)
      allow(log).to receive(:report_error).and_call_original

      described_class.call(
        adventure: adventure, loop: next_loop, log: log, ai: ai,
        result: {
          "facts" => [],
          "invalidates" => [{ "fact_id" => foreign_fact.id, "reason" => "cross-adv attempt" }],
        },
      )

      foreign_fact.reload
      expect(foreign_fact.invalidated_at_loop_id).to be_nil
      expect(log).to have_received(:report_error)
    end

    it "emits narrative_fact_invalidated play_log per invalidation" do
      stub_embeddings(1)

      expect {
        described_class.call(
          adventure: adventure, loop: next_loop, log: log, ai: ai,
          result: {
            "facts" => [{ "text" => "replacement", "kind" => "state", "polarity" => "asserts" }],
            "invalidates" => [{ "fact_id" => old_state.id, "reason" => "gone", "replacement_source_idx" => 0 }],
          },
        )
      }.to change { PlayLog.where(event_type: "narrative_fact_invalidated", adventure_id: adventure.id).count }.by(1)
    end
  end

  describe "idempotency" do
    it "is safe to reapply the same result twice (partial unique index dedupes)" do
      stub_embeddings(2)

      payload = {
        "facts" => [
          { "text" => "A", "kind" => "event", "polarity" => "asserts" },
          { "text" => "B", "kind" => "event", "polarity" => "asserts" },
        ],
        "invalidates" => [],
      }

      described_class.call(adventure: adventure, loop: loop_row, log: log, ai: ai, result: payload)
      expect {
        described_class.call(adventure: adventure, loop: loop_row, log: log, ai: ai, result: payload)
      }.not_to change {
        AdventureNarrativeFact.where(adventure_id: adventure.id,
                                     introduced_at_loop_id: loop_row.id,
                                     source: "loremaster").count
      }
    end
  end

  describe "seed source" do
    it "writes facts with source='seed' and loop id null when called with loop: nil" do
      stub_embeddings(1)

      outcome = described_class.call(
        adventure: adventure, loop: nil, log: log, ai: ai,
        source: "seed",
        result: { "facts" => [{ "text" => "seed", "kind" => "state", "polarity" => "asserts" }],
                  "invalidates" => [] },
      )

      row = AdventureNarrativeFact.find(outcome.inserted_fact_ids.first)
      expect(row.source).to eq("seed")
      expect(row.introduced_at_loop_id).to be_nil
    end
  end

  describe "per-row failure" do
    it "reports a per-row insert error via log.report_error and continues with the next fact" do
      stub_embeddings(2)
      allow(log).to receive(:report_error).and_call_original

      call_count = 0
      allow(AdventureNarrativeFact).to receive(:create!).and_wrap_original do |orig, **attrs|
        call_count += 1
        raise ActiveRecord::StatementInvalid, "simulated DB failure on first insert" if call_count == 1

        orig.call(**attrs)
      end

      outcome = described_class.call(
        adventure: adventure, loop: loop_row, log: log, ai: ai,
        result: {
          "facts" => [
            { "text" => "will fail",  "kind" => "event", "polarity" => "asserts" },
            { "text" => "will succeed", "kind" => "event", "polarity" => "asserts" },
          ],
          "invalidates" => [],
        },
      )

      expect(outcome.inserted_fact_ids.length).to eq(1)
      expect(log).to have_received(:report_error).with(
        instance_of(ActiveRecord::StatementInvalid),
        hash_including(context: hash_including(source: "apply_results.insert_fact", source_idx: 0))
      )
    end
  end
end
