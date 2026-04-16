# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::PathfinderCastingAbility do
  describe ".primary_for_class" do
    it "returns intelligence for wizard" do
      expect(described_class.primary_for_class("Wizard")).to eq(:intelligence)
    end

    it "returns wisdom for cleric" do
      expect(described_class.primary_for_class("cleric")).to eq(:wisdom)
    end

    it "picks the first recognized class in a compound string" do
      expect(described_class.primary_for_class("Fighter 2 / Wizard 3")).to eq(:intelligence)
    end

    it "returns nil for a non-caster" do
      expect(described_class.primary_for_class("fighter")).to be_nil
    end
  end
end
