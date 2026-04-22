# frozen_string_literal: true

require "rails_helper"

# C7 of the narrative facts plan — creation-time seeding service.
#
# Verifies that `SeedFromAdventure`:
#   * Assembles the correct seed input (premise / enriched_world / opening
#     narrative / initial contexts / NPCs incl. adventure-scoped records
#     from Embellisher Expand / clues / locations) and threads it into the
#     Loremaster seed prompt.
#   * Writes facts with `source: "seed"` and `introduced_at_loop_id: nil`
#     via the shared `Lore::ApplyResults` path (one batched embeddings
#     call, rows keyed by `source_idx`).
#   * On an AI-layer failure, reports to Sentry via `log.report_error`
#     AND emits a `seed_failure` play_log event, then returns an empty
#     outcome — adventure creation must not blow up because seeding did.
RSpec.describe DungeonMaster::Lore::SeedFromAdventure do
  around do |ex|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ex.run
    ActiveJob::Base.queue_adapter = original
  end

  let(:story)     { create(:story, premise: "The party is adrift in the middle of the open ocean.") }
  let(:user)      { create(:user) }
  let(:adventure) do
    create(:adventure, story: story, user: user,
           enriched_world: { "climate" => "tropical", "perils" => ["storms", "leviathans"] })
  end

  let(:log) { DungeonMaster::Logging.new(adventure: adventure, user: user, dm_service: "standard") }
  let(:ai)  { instance_double(DungeonMaster::AiClient) }

  def vec(seed)
    Array.new(1536) { |i| i.zero? ? seed.to_f : 0.0 }
  end

  def stub_embeddings_identity
    allow(ai).to receive(:embeddings) do |**kw|
      Array(kw[:texts]).each_with_index.map { |_, i| vec(i + 1) }
    end
  end

  def stub_chat(return_hash)
    allow(ai).to receive(:chat).and_return(return_hash.to_json)
    allow(ai).to receive(:parse_json).and_return(return_hash)
    allow(ai).to receive(:last_parse_status).and_return("success")
    allow(ai).to receive(:last_model_used).and_return("gpt-4.1-mini")
    allow(ai).to receive(:last_usage).and_return({ "total_tokens" => 42 })
  end

  describe "seed-input assembly" do
    before do
      story.story_locations.create!(name: "The Wreckage", description: "A splintered raft.")
      adventure.adventure_messages.create!(role: "dm", message_type: "narrative",
                                           content: "Salt wind whips the waves as dawn breaks.")
      StoryNpc.create!(story: story, adventure: nil, source: "manual",
                       name: "Captain Rook", role: "informant", attitude: "friendly",
                       description: "A weathered old salt lashed to the mast.")
      StoryNpc.create!(story: story, adventure: adventure, source: "embellisher",
                       name: "The Drowned Steward", role: "antagonist", attitude: "unfriendly",
                       description: "A waterlogged revenant that knows too much.")
      StoryClue.create!(story: story, adventure: nil, source: "manual",
                        title: "Soaked logbook", description: "Pages smeared with ink and salt.",
                        discovery_method: "exploration", difficulty: "moderate")
      stub_embeddings_identity
    end

    it "renders Loremaster's seed prompt with the full creation-time input" do
      captured = nil
      allow(ai).to receive(:chat) do |**kw|
        captured = kw[:system_prompt]
        { "facts" => [], "invalidates" => [], "reasoning" => "" }.to_json
      end
      allow(ai).to receive(:parse_json).and_return(
        { "facts" => [], "invalidates" => [], "reasoning" => "" }
      )
      allow(ai).to receive(:last_parse_status).and_return("success")
      allow(ai).to receive(:last_model_used).and_return("gpt-4.1-mini")
      allow(ai).to receive(:last_usage).and_return({})

      described_class.call(adventure: adventure, user: user, ai: ai, log: log)

      expect(captured).to include("This is a **seed call**")
      expect(captured).to include(story.premise)
      expect(captured).to include("Salt wind whips the waves")
      expect(captured).to include("Captain Rook")
      expect(captured).to include("The Drowned Steward"),
        "expected adventure-scoped Embellisher Expand NPC to be in the prompt"
      expect(captured).to include("Soaked logbook")
      expect(captured).to include("The Wreckage")
      expect(captured).to include("tropical"),
        "expected enriched_world JSONB to be rendered as text"
    end

    it "writes fact rows with source='seed' and introduced_at_loop_id nil, in one batched embeddings call" do
      stub_chat(
        "facts" => [
          { "text" => "the party is adrift in the middle of the open ocean",
            "kind" => "state", "entities" => ["party", "ocean"], "polarity" => "asserts" },
          { "text" => "Captain Rook is lashed to the mast",
            "kind" => "entity", "entities" => ["Captain Rook"], "polarity" => "asserts" },
        ],
        "invalidates" => [],
        "reasoning" => "seed from premise",
      )

      described_class.call(adventure: adventure, user: user, ai: ai, log: log)

      rows = AdventureNarrativeFact.where(adventure_id: adventure.id).order(:id).to_a
      expect(rows.length).to eq(2)
      expect(rows.map(&:source).uniq).to eq(["seed"])
      expect(rows.map(&:introduced_at_loop_id).uniq).to eq([nil])
      expect(rows.map(&:source_idx)).to eq([0, 1])
      expect(rows.map(&:kind)).to eq(%w[state entity])

      expect(ai).to have_received(:embeddings).once.with(
        texts: [
          "the party is adrift in the middle of the open ocean",
          "Captain Rook is lashed to the mast",
        ],
        model: "text-embedding-3-small",
      )
    end
  end

  describe "lossy-on-failure" do
    it "reports to Sentry + emits seed_failure play_log and returns an empty outcome when the AI call raises" do
      allow(ai).to receive(:chat).and_raise(DungeonMaster::AiError, "simulated upstream failure")
      allow(ai).to receive(:last_model_used).and_return("gpt-4.1-mini")
      allow(ai).to receive(:last_usage).and_return({})

      reports = []
      allow(log).to receive(:report_error).and_wrap_original do |orig, exception, **kwargs|
        reports << { exception: exception, kwargs: kwargs }
        orig.call(exception, **kwargs)
      end

      outcome = described_class.call(adventure: adventure, user: user, ai: ai, log: log)

      expect(outcome.inserted_fact_ids).to eq([])
      expect(outcome.invalidated_fact_ids).to eq([])

      expect(reports.any? { |r| r[:kwargs].dig(:context, :step) == "loremaster_seed" }).to be(true),
        "expected log.report_error with step: 'loremaster_seed' but saw: #{reports.map { _1[:kwargs] }}"

      failure_log = PlayLog.where(adventure_id: adventure.id, event_type: "seed_failure").last
      expect(failure_log).to be_present
      expect(failure_log.prompt_summary).to include("Loremaster seed failed")
    end
  end
end
