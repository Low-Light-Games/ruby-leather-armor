# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdventureNarrativeFact, type: :model do
  let(:adventure) { create(:adventure) }

  describe "associations" do
    it { should belong_to(:adventure) }
    it { should belong_to(:introduced_at_loop).class_name("AdventureLoop").optional }
    it { should belong_to(:invalidated_at_loop).class_name("AdventureLoop").optional }
    it { should belong_to(:invalidated_by_fact).class_name("AdventureNarrativeFact").optional }
  end

  describe "validations" do
    it { should validate_inclusion_of(:kind).in_array(%w[event state entity]) }
    it { should validate_inclusion_of(:polarity).in_array(%w[asserts negates]) }
    it { should validate_inclusion_of(:source).in_array(%w[seed loremaster]) }
    it { should validate_presence_of(:text) }
  end

  describe "round-trip" do
    it "persists a seed fact with all fields populated" do
      fact = AdventureNarrativeFact.create!(
        adventure: adventure,
        text: "The party is in the middle of the ocean.",
        kind: "state",
        entities: ["party", "ocean"],
        polarity: "asserts",
        source: "seed",
        source_idx: nil,
        embedding: Array.new(1536) { 0.01 },
      )

      reloaded = AdventureNarrativeFact.find(fact.id)
      expect(reloaded.kind).to eq("state")
      expect(reloaded.entities).to eq(["party", "ocean"])
      expect(reloaded.source).to eq("seed")
      expect(reloaded.embedding.size).to eq(1536)
      expect(reloaded.active?).to be true
    end
  end

  describe "scopes" do
    it "splits active vs invalidated facts" do
      loop_row = AdventureLoop.create!(
        adventure: adventure,
        registry_entry_uuid: SecureRandom.uuid,
        sequence_index: 0,
      )
      active = AdventureNarrativeFact.create!(
        adventure: adventure, text: "Active fact", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 0,
      )
      invalidated = AdventureNarrativeFact.create!(
        adventure: adventure, text: "Invalidated fact", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 1,
        invalidated_at_loop: loop_row,
      )

      expect(AdventureNarrativeFact.active).to include(active)
      expect(AdventureNarrativeFact.active).not_to include(invalidated)
      expect(AdventureNarrativeFact.invalidated).to include(invalidated)
      expect(AdventureNarrativeFact.invalidated).not_to include(active)
    end
  end

  describe "partial unique index on (adventure_id, introduced_at_loop_id, source_idx) WHERE source = 'loremaster'" do
    let(:loop_row) do
      AdventureLoop.create!(
        adventure: adventure,
        registry_entry_uuid: SecureRandom.uuid,
        sequence_index: 0,
      )
    end

    it "rejects duplicate (adventure_id, introduced_at_loop_id, source_idx) for loremaster rows" do
      AdventureNarrativeFact.create!(
        adventure: adventure, text: "First", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 0,
      )

      expect {
        AdventureNarrativeFact.create!(
          adventure: adventure, text: "Second", kind: "event",
          polarity: "asserts", source: "loremaster",
          introduced_at_loop: loop_row, source_idx: 0,
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "does not constrain seed rows (source: 'seed', source_idx: nil)" do
      AdventureNarrativeFact.create!(
        adventure: adventure, text: "Seed A", kind: "state",
        polarity: "asserts", source: "seed",
      )
      expect {
        AdventureNarrativeFact.create!(
          adventure: adventure, text: "Seed B", kind: "state",
          polarity: "asserts", source: "seed",
        )
      }.not_to raise_error
    end

    it "allows the same source_idx across different loop ids" do
      other_loop = AdventureLoop.create!(
        adventure: adventure,
        registry_entry_uuid: SecureRandom.uuid,
        sequence_index: 1,
      )
      AdventureNarrativeFact.create!(
        adventure: adventure, text: "Turn 1 fact", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 0,
      )
      expect {
        AdventureNarrativeFact.create!(
          adventure: adventure, text: "Turn 2 fact", kind: "event",
          polarity: "asserts", source: "loremaster",
          introduced_at_loop: other_loop, source_idx: 0,
        )
      }.not_to raise_error
    end
  end

  describe "has_neighbors :embedding" do
    it "orders rows by cosine distance to a query vector" do
      loop_row = AdventureLoop.create!(
        adventure: adventure,
        registry_entry_uuid: SecureRandom.uuid,
        sequence_index: 0,
      )
      near = AdventureNarrativeFact.create!(
        adventure: adventure, text: "Near fact", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 0,
        embedding: Array.new(1536) { |i| i.zero? ? 1.0 : 0.0 },
      )
      far = AdventureNarrativeFact.create!(
        adventure: adventure, text: "Far fact", kind: "event",
        polarity: "asserts", source: "loremaster",
        introduced_at_loop: loop_row, source_idx: 1,
        embedding: Array.new(1536) { |i| i == 100 ? 1.0 : 0.0 },
      )

      query = Array.new(1536) { |i| i.zero? ? 1.0 : 0.0 }
      results = AdventureNarrativeFact
                  .nearest_neighbors(:embedding, query, distance: "cosine")
                  .first(2)

      expect(results.first.id).to eq(near.id)
      expect(results.last.id).to eq(far.id)
    end
  end
end
