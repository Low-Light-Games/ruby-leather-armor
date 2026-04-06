# frozen_string_literal: true

require "rails_helper"

RSpec.describe CharacterStats::SkillRanksValidator do
  describe ".errors_for" do
    it "returns no errors for empty skill ranks" do
      sheet = build(:sheet, skill_ranks: {}, character_class: "fighter")
      expect(described_class.errors_for(sheet)).to eq([])
    end

    it "rejects ranks without a character class" do
      sheet = build(:sheet, character_class: nil, skill_ranks: { "Climb" => 1 })
      expect(described_class.errors_for(sheet).first).to include("character class")
    end

    it "rejects unknown skill names" do
      sheet = build(:sheet, character_class: "fighter", skill_ranks: { "Fake Skill" => 1 })
      expect(described_class.errors_for(sheet).first).to include("Unknown skill")
    end

    it "rejects ranks above the per-skill cap" do
      sheet = build(:sheet,
                    character_class: "fighter",
                    level: 1,
                    intelligence: 10,
                    skill_ranks: { "Climb" => 5 })
      expect(described_class.errors_for(sheet).first).to include("maximum")
    end

    it "rejects when total spent exceeds budget" do
      # Level 1 fighter, Int 10: per-level skill points = max(1, 2+0)=2, total = 8 (×4 for 1st level).
      sheet = build(:sheet,
                    character_class: "fighter",
                    level: 1,
                    intelligence: 10,
                    race: "elf",
                    skill_ranks: {
                      "Climb" => 4,
                      "Swim" => 4,
                    })
      errors = described_class.errors_for(sheet)
      expect(errors.any? { |e| e.include?("exceed") && e.include?("budget") }).to be true
    end

    it "accepts a legal allocation" do
      sheet = build(:sheet,
                    character_class: "fighter",
                    level: 1,
                    intelligence: 10,
                    race: "elf",
                    skill_ranks: { "Climb" => 4 })
      expect(described_class.errors_for(sheet)).to eq([])
    end
  end
end
