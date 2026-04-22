# frozen_string_literal: true

require "rails_helper"

RSpec.describe DmConfig, "narrative facts defaults" do
  subject(:config) { described_class.new(settings: {}) }

  describe "DEFAULTS" do
    it "exposes narrative_facts_top_k" do
      expect(DmConfig::DEFAULTS["narrative_facts_top_k"]).to eq(8)
    end

    it "exposes narrative_facts_active_window" do
      expect(DmConfig::DEFAULTS["narrative_facts_active_window"]).to eq(20)
    end
  end

  describe "#narrative_facts_top_k" do
    it "reads the default when not explicitly set" do
      expect(config.narrative_facts_top_k).to eq(8)
    end

    it "honors a per-instance override" do
      config.set("narrative_facts_top_k", 5)
      expect(config.narrative_facts_top_k).to eq(5)
    end
  end

  describe "#narrative_facts_active_window" do
    it "reads the default when not explicitly set" do
      expect(config.narrative_facts_active_window).to eq(20)
    end

    it "honors a per-instance override" do
      config.set("narrative_facts_active_window", 50)
      expect(config.narrative_facts_active_window).to eq(50)
    end
  end
end
