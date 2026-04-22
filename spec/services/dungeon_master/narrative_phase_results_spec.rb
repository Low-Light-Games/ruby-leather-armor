# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::NarrativePhaseResults do
  describe ".narrated" do
    it "produces a hash keyed by action: :narrated with the base payload" do
      hash = described_class.narrated(
        narrative: "You push open the door.",
        adventure_complete: false,
      ).to_h

      expect(hash).to eq(
        action: :narrated,
        narrative: "You push open the door.",
        adventure_complete: false,
      )
    end

    it "merges the extras after the base payload" do
      hash = described_class.narrated(
        narrative: "A hush falls.",
        adventure_complete: true,
        extras: { encounter_triggered: true, action_outcomes: %w[push disarm] },
      ).to_h

      expect(hash).to include(
        action: :narrated,
        narrative: "A hush falls.",
        adventure_complete: true,
        encounter_triggered: true,
        action_outcomes: %w[push disarm],
      )
    end

    it "treats nil extras as empty" do
      hash = described_class.narrated(
        narrative: "",
        adventure_complete: false,
        extras: nil,
      ).to_h

      expect(hash).to eq(
        action: :narrated,
        narrative: "",
        adventure_complete: false,
      )
    end
  end

  describe ".awaiting_initiative" do
    let(:intent) { { intention: "I draw my sword" } }
    let(:creature_data) { { names: %w[goblin], hp: [7] } }
    let(:mutations) { { "player" => { "conditions_add" => ["on_guard"] } } }

    it "produces a hash keyed by action: :awaiting_initiative with the base payload" do
      hash = described_class.awaiting_initiative(
        intent: intent,
        creature_data: creature_data,
        mutations: mutations,
      ).to_h

      expect(hash).to eq(
        action: :awaiting_initiative,
        intent: intent,
        creature_data: creature_data,
        mutations: mutations,
      )
    end

    it "merges the extras after the base payload" do
      hash = described_class.awaiting_initiative(
        intent: intent,
        creature_data: creature_data,
        mutations: mutations,
        extras: { opener_outcome: "goblin_staggered" },
      ).to_h

      expect(hash).to include(
        action: :awaiting_initiative,
        opener_outcome: "goblin_staggered",
      )
    end
  end
end
