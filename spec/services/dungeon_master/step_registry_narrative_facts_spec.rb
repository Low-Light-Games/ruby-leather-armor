# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::StepRegistry, "narrative facts steps" do
  describe "loremaster" do
    subject(:entry) { described_class::STEPS["loremaster"] }

    it "is registered" do
      expect(entry).not_to be_nil
    end

    it "is a pipeline step (admin UI knob)" do
      expect(entry.pipeline).to be true
    end

    it "has a mid-tier model hint" do
      expect(entry.model_hint).to match(/mid-tier model/i)
    end
  end

  describe "embedding" do
    subject(:entry) { described_class::STEPS["embedding"] }

    it "is registered" do
      expect(entry).not_to be_nil
    end

    it "is NOT a pipeline step (AiLog event_type only, not an admin knob)" do
      expect(entry.pipeline).to be false
    end

    it "has no model_hint (its model is hardcoded in AiClient#embeddings)" do
      expect(entry.model_hint).to be_nil
    end

    it "is accepted as a PlayLog event_type" do
      expect(PlayLog::EVENT_TYPES).to include("embedding")
    end
  end

  it "both entries appear in PlayLog::EVENT_TYPES" do
    expect(PlayLog::EVENT_TYPES).to include("loremaster", "embedding")
  end
end
