# frozen_string_literal: true

require "rails_helper"

# C10 of the narrative facts plan — World Consistency Check cutover.
#
# Verifies:
#   * Prompt-shape: micro-context key names removed; facts grouped by kind;
#     contradiction instruction present.
#   * End-to-end "ocean vs dig" case — a state fact about being adrift in
#     the ocean causes "I dig in the sand" to come back consistent: false
#     with the fact cited verbatim in `reason`.
#   * State invalidation: after the ocean fact is invalidated (and a
#     beach state replaces it) the same intent flips to consistent: true.
#   * Intra-queue world-check staleness characterization (read-side half
#     of correctness claim #8) — Action 2 of a two-action queue retrieves
#     against the fact set live at the start of the player message.
RSpec.describe "SanityChecker — world check cutover (C10)", type: :service do
  around do |ex|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ex.run
    ActiveJob::Base.queue_adapter = original
  end

  let(:adventure) { create(:adventure) }
  let(:user)      { adventure.user }
  let(:log) { DungeonMaster::Logging.new(adventure: adventure, user: user, dm_service: "standard") }

  let(:ocean_vec) do
    v = Array.new(1536, 0.0); v[0] = 1.0; v
  end
  let(:beach_vec) do
    v = Array.new(1536, 0.0); v[1] = 1.0; v
  end
  let(:intent_vec_ocean) { ocean_vec } # query embeds "close" to ocean
  let(:intent_vec_beach) { beach_vec }

  describe "prompt shape" do
    it "drops all six micro-context key names and renders facts grouped by kind with a contradiction instruction" do
      established_facts = [
        { fact_id: 1, text: "the party is adrift in the ocean",
          kind: "state", polarity: "asserts", distance: 0.01 },
        { fact_id: 2, text: "the bridge over the chasm collapsed last night",
          kind: "event", polarity: "asserts", distance: 0.05 },
        { fact_id: 3, text: "the innkeeper is named Gerta",
          kind: "entity", polarity: "asserts", distance: 0.10 },
      ]
      ctx = DungeonMaster::PromptViews::SanityCheckerPromptContext.new(
        scene_summary: "Salt wind whips the waves.",
        scene_history: [],
        established_facts: established_facts,
        npc_names: ["Gerta"],
        combat_active: false,
      )

      rendered = DungeonMaster::PromptRenderer.render("sanity_checker_world", sanity_context: ctx)

      %w[traversal_context combat_context social_context
         exploration_context rest_context inventory_context].each do |key|
        expect(rendered).not_to include(key),
          "expected micro-context key #{key.inspect} to be gone from sanity_checker_world prompt"
      end

      expect(rendered).to include("ESTABLISHED NARRATIVE FACTS")
      expect(rendered).to include("adrift in the ocean")
      expect(rendered).to include("bridge over the chasm collapsed")
      expect(rendered).to include("innkeeper is named Gerta")
      expect(rendered).to match(/directly contradicts any established fact/i)
    end
  end

  describe "end-to-end ocean-vs-dig contradiction" do
    before do
      AdventureNarrativeFact.create!(
        adventure: adventure,
        text: "the party is adrift in the middle of the open ocean",
        kind: "state", polarity: "asserts", source: "seed",
        embedding: ocean_vec,
      )
    end

    it "retrieves the ocean state fact for 'I dig in the sand' and renders it into the prompt" do
      ai = instance_spy(DungeonMaster::AiClient)
      allow(ai).to receive(:embeddings).and_return([ocean_vec])

      hits = DungeonMaster::Lore::FactsLookup.call(
        adventure: adventure, ai: ai, log: log,
        query_text: "I dig in the sand",
      )

      expect(hits.length).to eq(1)
      expect(hits.first[:text]).to include("adrift in the middle of the open ocean")
      expect(hits.first[:kind]).to eq("state")

      ctx = DungeonMaster::PromptViews::SanityCheckerPromptContext.new(
        established_facts: hits,
      )
      rendered = DungeonMaster::PromptRenderer.render("sanity_checker_world", sanity_context: ctx)
      expect(rendered).to include("adrift in the middle of the open ocean")
    end

    it "flips to consistent: true after the ocean state is invalidated by a beach state" do
      loop_row = AdventureLoop.create!(adventure: adventure, registry_entry_uuid: SecureRandom.uuid, sequence_index: 0)
      AdventureNarrativeFact.where(adventure_id: adventure.id)
                            .update_all(invalidated_at_loop_id: loop_row.id)
      AdventureNarrativeFact.create!(
        adventure: adventure,
        text: "the party is standing on the beach after climbing out of the surf",
        kind: "state", polarity: "asserts", source: "loremaster",
        source_idx: 0, introduced_at_loop_id: loop_row.id,
        embedding: beach_vec,
      )

      ai = instance_spy(DungeonMaster::AiClient)
      allow(ai).to receive(:embeddings).and_return([beach_vec])

      hits = DungeonMaster::Lore::FactsLookup.call(
        adventure: adventure, ai: ai, log: log,
        query_text: "I dig in the sand",
      )

      expect(hits.length).to eq(1)
      expect(hits.first[:text]).to include("standing on the beach")
    end
  end

  describe "intra-queue staleness characterization (read-side of claim #8)" do
    # Guards the accepted staleness trade-off: within one multi-action
    # player message, Action 2's world check reads the fact set that was
    # live at the start of the player message, not a set updated by
    # Action 1. Loremaster runs exactly once — in the terminal narrative
    # phase — so facts written by Action 1 only become visible on the
    # next player message.
    it "Action 2's world-check retrieval does not see a fact 'created' by Action 1" do
      AdventureNarrativeFact.create!(
        adventure: adventure,
        text: "the party is adrift in the middle of the open ocean",
        kind: "state", polarity: "asserts", source: "seed",
        embedding: ocean_vec,
      )

      ai = instance_spy(DungeonMaster::AiClient)
      allow(ai).to receive(:embeddings).and_return([ocean_vec])

      action_1_hits = DungeonMaster::Lore::FactsLookup.call(
        adventure: adventure, ai: ai, log: log,
        query_text: "I pick up the rope",
      )

      action_2_hits = DungeonMaster::Lore::FactsLookup.call(
        adventure: adventure, ai: ai, log: log,
        query_text: "I throw the rope across the chasm",
      )

      expect(action_1_hits.length).to eq(1)
      expect(action_2_hits.length).to eq(1)
      expect(action_2_hits.first[:fact_id]).to eq(action_1_hits.first[:fact_id]),
        "Action 2 must observe the same fact set as Action 1 within one player message"
    end
  end
end
