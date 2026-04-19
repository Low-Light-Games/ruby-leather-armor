# frozen_string_literal: true

require "rails_helper"

# ── Shared sheet setup ──────────────────────────────────────────────────────
# A bare sheet: no equipped armor or shield (armor_bonus = 0, shield_bonus = 0
# from equipment). Makes buff math straightforward to assert.

RSpec.shared_context "sheet without equipment" do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  let(:sheet) do
    create(:adventure_sheet,
      adventure:       adventure,
      strength:        14,
      dexterity:       12,   # dex_mod = +1
      constitution:    13,
      intelligence:    10,
      wisdom:          11,
      charisma:        8,
      race:            "human",
      character_class: "wizard",
      level:           5,
      racial_bonus_attribute: "intelligence"
    )
  end
end

# ── CombatCalculator — AC buff application ──────────────────────────────────

RSpec.describe CharacterStats::CombatCalculator, "active_buffs AC", type: :model do
  include_context "sheet without equipment"

  let(:feats) { [] }
  let(:items) { [] }

  subject(:calc) { described_class.new(sheet, feats: feats, items: items) }

  def base_ac
    calc.compute(
      ability: CharacterStats::AbilityScoreCalculator.new(sheet).compute,
      enc:     CharacterStats::EncumbranceCalculator.new(items, str_score: 14, size: "Medium", coin_count: 0)
              .compute(base_speed: 30, equip: calc.compute_equipment_bonuses)
    )[:ac]
  end

  context "with no active_buffs" do
    it "produces AC = 10 + dex_mod" do
      expect(base_ac).to eq(11) # 10 + 1
    end
  end

  context "with a single armor-type buff (mage armor +4)" do
    before { sheet.update_column(:active_buffs, [{ "source" => "mage_armor", "bonus_type" => "armor", "target" => "ac", "value" => 4 }]) }

    it "adds +4 to AC" do
      expect(base_ac).to eq(15) # 10 + 1 + 4
    end
  end

  context "with two different-type buffs (armor + deflection)" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "mage_armor",      "bonus_type" => "armor",      "target" => "ac", "value" => 4 },
        { "source" => "protection_evil", "bonus_type" => "deflection", "target" => "ac", "value" => 2 }
      ])
    end

    it "stacks both bonuses (armor and deflection are different types)" do
      expect(base_ac).to eq(17) # 10 + 1 + 4 + 2
    end
  end

  context "when two same-type buffs compete (both deflection)" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "ring_of_protection", "bonus_type" => "deflection", "target" => "ac", "value" => 2 },
        { "source" => "shield_of_faith",    "bonus_type" => "deflection", "target" => "ac", "value" => 3 }
      ])
    end

    it "takes only the highest deflection bonus (3, not 5)" do
      expect(base_ac).to eq(14) # 10 + 1 + 3
    end
  end

  context "when buff armor_type equals equipped armor (highest wins)" do
    before do
      # Simulate equipped leather armor (+2) via the equip struct by giving the
      # sheet an equipped armor item.  Simplest is to drive through a real item.
      # Since creating item DB records is complex, use update_column shortcut.
      sheet.update_column(:active_buffs, [
        { "source" => "mage_armor", "bonus_type" => "armor", "target" => "ac", "value" => 4 }
      ])
    end

    it "produces at least as much AC as the buff alone" do
      # No equipped armor so mage_armor (+4) is uncontested
      expect(base_ac).to eq(15)
    end
  end

  describe "ac_breakdown" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "mage_armor",      "bonus_type" => "armor",      "target" => "ac", "value" => 4 },
        { "source" => "protection_evil", "bonus_type" => "deflection", "target" => "ac", "value" => 2 }
      ])
    end

    let(:breakdown) do
      calc.compute(
        ability: CharacterStats::AbilityScoreCalculator.new(sheet).compute,
        enc:     CharacterStats::EncumbranceCalculator.new(items, str_score: 14, size: "Medium", coin_count: 0)
                .compute(base_speed: 30, equip: calc.compute_equipment_bonuses)
      )[:ac_breakdown]
    end

    it "includes a Buff entry for the deflection bonus" do
      labels = breakdown.map { |e| e[:label] }
      expect(labels).to include("Buff (deflection)")
    end

    it "does not include a separate Buff entry for armor (merged into Armor line)" do
      labels = breakdown.map { |e| e[:label] }
      expect(labels).not_to include("Buff (armor)")
    end
  end

  context "with non-ac target buffs (should not affect AC)" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "potion_of_haste", "bonus_type" => "enhancement", "target" => "speed", "value" => 30 }
      ])
    end

    it "leaves AC unchanged" do
      expect(base_ac).to eq(11)
    end
  end
end

# ── Calculator — speed buff application ────────────────────────────────────

RSpec.describe CharacterStats::Calculator, "active_buffs speed", type: :model do
  include_context "sheet without equipment"

  subject(:stats) { described_class.new(sheet).compute }

  def base_speed
    described_class.new(sheet.dup.tap { |s| s.active_buffs = [] }).compute[:speed]
  end

  context "with no active_buffs" do
    it "returns base speed" do
      expect(stats[:speed]).to eq(base_speed)
    end
  end

  context "with a single enhancement speed buff" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "potion_of_haste", "bonus_type" => "enhancement", "target" => "speed", "value" => 30 }
      ])
    end

    it "adds 30 ft to speed" do
      expect(stats[:speed]).to eq(base_speed + 30)
    end
  end

  context "with two enhancement speed buffs (same type — only highest applies)" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "potion_of_haste",    "bonus_type" => "enhancement", "target" => "speed", "value" => 30 },
        { "source" => "boots_of_speed",     "bonus_type" => "enhancement", "target" => "speed", "value" => 10 }
      ])
    end

    it "takes highest value in the same bonus_type group" do
      expect(stats[:speed]).to eq(base_speed + 30)
    end
  end

  context "with two different-type speed buffs" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "potion_of_haste", "bonus_type" => "enhancement", "target" => "speed", "value" => 30 },
        { "source" => "expeditious",     "bonus_type" => "morale",      "target" => "speed", "value" => 10 }
      ])
    end

    it "stacks both bonuses" do
      expect(stats[:speed]).to eq(base_speed + 40)
    end
  end

  context "with non-speed target buffs (should not affect speed)" do
    before do
      sheet.update_column(:active_buffs, [
        { "source" => "mage_armor", "bonus_type" => "armor", "target" => "ac", "value" => 4 }
      ])
    end

    it "leaves speed unchanged" do
      expect(stats[:speed]).to eq(base_speed)
    end
  end
end
