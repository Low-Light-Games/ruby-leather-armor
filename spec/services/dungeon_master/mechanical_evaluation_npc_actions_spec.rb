# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::MechanicalEvaluationNpcActions do
  describe ".filter_for_combat_finish" do
    let(:routine) { { "actor" => "Goblin", "action" => "attack", "modifier" => 2 } }
    let(:immediate) { { "actor" => "Goblin", "action" => "AoO", "modifier" => 2, "immediate" => true } }

    it "returns all actions when combat is not active" do
      out = described_class.filter_for_combat_finish([routine, immediate], combat_active: false)
      expect(out.size).to eq(2)
    end

    it "keeps only immediate-flagged actions when combat is active" do
      out = described_class.filter_for_combat_finish([routine, immediate], combat_active: true)
      expect(out.size).to eq(1)
      expect(out.first[:action]).to eq("AoO")
    end

    it "accepts timing: immediate" do
      timed = { actor: "Goblin", action: "AoO", modifier: 1, timing: "immediate" }
      out = described_class.filter_for_combat_finish([routine, timed], combat_active: true)
      expect(out.map { |h| h[:action] }).to eq(["AoO"])
    end
  end
end
