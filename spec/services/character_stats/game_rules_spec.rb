# frozen_string_literal: true

require "rails_helper"

RSpec.describe CharacterStats::GameRules do
  describe "ABILITIES" do
    it "lists the six core ability scores" do
      expect(described_class::ABILITIES).to eq(%w[strength dexterity constitution intelligence wisdom charisma])
    end
  end

  describe "CLASS_DATA" do
    it "defines data for all supported classes" do
      expect(described_class::CLASS_DATA.keys).to include("fighter", "rogue", "wizard", "barbarian")
    end

    it "each entry has hit_die, bab, good_saves, and skill_points" do
      described_class::CLASS_DATA.each do |klass, data|
        expect(data).to include(:hit_die, :bab, :good_saves, :skill_points), "#{klass} is missing keys"
      end
    end
  end

  describe "RACE_DATA" do
    it "defines data for all supported races including human" do
      expect(described_class::RACE_DATA).to have_key("human")
      expect(described_class::RACE_DATA.keys).to include("elf", "dwarf", "halfling", "gnome", "half_elf", "half_orc")
    end

    it "each entry has size, speed, fixed, flex_count, and skill_bonuses" do
      described_class::RACE_DATA.each do |race, data|
        expect(data).to include(:size, :speed, :fixed, :flex_count, :skill_bonuses), "#{race} is missing keys"
      end
    end
  end

  describe "CARRY_CAPACITY" do
    it "has an entry for STR 0 through 29" do
      expect(described_class::CARRY_CAPACITY.length).to eq(30)
    end

    it "each entry is a 3-element array [light, medium, heavy]" do
      described_class::CARRY_CAPACITY.each do |entry|
        expect(entry.length).to eq(3)
      end
    end
  end

  describe "SKILLS" do
    it "includes Perception, Stealth, and Bluff" do
      names = described_class::SKILLS.map { |s| s[:name] }
      expect(names).to include("Perception", "Stealth", "Bluff")
    end

    it "each skill has required keys" do
      described_class::SKILLS.each do |skill|
        expect(skill).to include(:name, :key, :trained_only, :acp), "#{skill[:name]} missing keys"
      end
    end
  end
end
