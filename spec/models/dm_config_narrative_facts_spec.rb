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

    it "exposes narrative_facts_embedding_model" do
      expect(DmConfig::DEFAULTS["narrative_facts_embedding_model"]).to eq("text-embedding-3-small")
    end
  end

  describe "EMBEDDING_MODELS whitelist" do
    it "includes the three expected model ids" do
      expect(DmConfig::EMBEDDING_MODEL_IDS).to contain_exactly(
        "text-embedding-3-small",
        "text-embedding-3-large",
        "text-embedding-ada-002",
      )
    end

    it "records a dimensions_override only when the model's native dim exceeds 1536" do
      small = DmConfig::EMBEDDING_MODELS.find { |m| m["id"] == "text-embedding-3-small" }
      large = DmConfig::EMBEDDING_MODELS.find { |m| m["id"] == "text-embedding-3-large" }
      ada   = DmConfig::EMBEDDING_MODELS.find { |m| m["id"] == "text-embedding-ada-002" }

      expect(small["native_dimensions"]).to eq(1536)
      expect(small["dimensions_override"]).to be_nil
      expect(large["native_dimensions"]).to eq(3072)
      expect(large["dimensions_override"]).to eq(1536)
      expect(ada["native_dimensions"]).to eq(1536)
      expect(ada["dimensions_override"]).to be_nil
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

  describe "#narrative_facts_embedding_model" do
    it "reads the default when not explicitly set" do
      expect(config.narrative_facts_embedding_model).to eq("text-embedding-3-small")
    end

    it "honors a whitelisted override" do
      config.set("narrative_facts_embedding_model", "text-embedding-3-large")
      expect(config.narrative_facts_embedding_model).to eq("text-embedding-3-large")
    end

    it "falls back to the default when the stored value is not whitelisted" do
      config.set("narrative_facts_embedding_model", "text-embedding-99-turbo")
      expect(config.narrative_facts_embedding_model).to eq("text-embedding-3-small")
    end
  end

  describe "#narrative_facts_embedding_dimensions" do
    it "returns nil for a 1536-native model (no truncation needed)" do
      config.set("narrative_facts_embedding_model", "text-embedding-3-small")
      expect(config.narrative_facts_embedding_dimensions).to be_nil
    end

    it "returns 1536 for a 3072-native model so the vector fits the column" do
      config.set("narrative_facts_embedding_model", "text-embedding-3-large")
      expect(config.narrative_facts_embedding_dimensions).to eq(1536)
    end
  end
end
