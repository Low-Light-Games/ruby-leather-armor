# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contextable do
  subject(:adventure) { create(:adventure) }

  describe "CONTEXT_FIELDS" do
    it "lists all expected context column names" do
      expect(described_class::CONTEXT_FIELDS).to include(
        "combat_context", "traversal_context", "social_context",
        "exploration_context", "rest_context", "inventory_context", "time_context"
      )
    end
  end

  describe "#merge_context!" do
    context "with the field name including _context suffix" do
      it "merges updates into the existing hash and persists" do
        adventure.update!(combat_context: { "round" => 1, "in_combat" => true })
        adventure.merge_context!(:combat_context, { "round" => 2 })
        expect(adventure.reload.combat_context).to eq("round" => 2, "in_combat" => true)
      end
    end

    context "with a bare field name (without _context suffix)" do
      it "infers the column name and merges correctly" do
        adventure.update!(traversal_context: { "terrain" => "forest" })
        adventure.merge_context!(:traversal, { "weather" => "rain" })
        expect(adventure.reload.traversal_context).to eq("terrain" => "forest", "weather" => "rain")
      end
    end

    context "with an unknown field name" do
      it "raises ArgumentError" do
        expect { adventure.merge_context!(:unknown, {}) }.to raise_error(ArgumentError, /Unknown context field/)
      end
    end

    it "treats a nil column value as an empty hash" do
      # social_context has a NOT NULL constraint so we can't write nil via SQL;
      # simulate what would happen if the column returned nil at the Ruby level
      # (e.g. a legacy row before the constraint existed).
      allow(adventure).to receive(:social_context).and_return(nil)
      allow(adventure).to receive(:update!).and_call_original
      expect { adventure.merge_context!(:social, { "npc" => "innkeeper" }) }.not_to raise_error
    end
  end

  describe "#reset_context!" do
    it "sets the context field to an empty hash" do
      adventure.update!(exploration_context: { "area" => "dungeon" })
      adventure.reset_context!(:exploration)
      expect(adventure.reload.exploration_context).to eq({})
    end
  end
end
