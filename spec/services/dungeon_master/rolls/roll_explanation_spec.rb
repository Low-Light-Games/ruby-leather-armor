# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Rolls::RollExplanation do
  describe ".from_summaries" do
    it "filters the no-mechanical placeholder after stripping the domain prefix" do
      text = described_class.from_summaries([
        "[SOCIAL] (no mechanical involvement in this domain)",
        "[TRAVERSAL] A Stealth check is required to approach the goblins unnoticed."
      ])

      expect(text).to eq("A Stealth check is required to approach the goblins unnoticed.")
    end

    it "falls back to the default text when every summary is filtered out" do
      text = described_class.from_summaries([
        "[SOCIAL] (no mechanical involvement in this domain)"
      ])

      expect(text).to eq(described_class::DEFAULT)
    end
  end
end
