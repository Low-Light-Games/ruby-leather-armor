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
      # Use human (not elf): elf's +2 Int would make final Int 12 → mod +1 → budget 12, and 4+4+4 ranks
      # would no longer exceed it. Human with Int 10 and no flex on Int: per-level = max(1, 2+0)=2, budget 8.
      # Three fighter class skills at max ranks (4+4+4 = 12) is legal per-skill but over budget.
      sheet = build(:sheet,
                    character_class: "fighter",
                    level: 1,
                    intelligence: 10,
                    race: "human",
                    racial_bonus_attribute: "strength",
                    skill_ranks: {
                      "Climb" => 4,
                      "Swim" => 4,
                      "Ride" => 4,
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
