# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Combat::AttackOptionBuilder do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet,
      adventure: adventure,
      character_class: "wizard",
      level: 3,
      strength: 10,
      dexterity: 16).tap(&:recompute_derived_stats!)
  end

  let!(:ray_of_frost) do
    SpellDefinition.create!(
      id: "ray_of_frost",
      name: "Ray of Frost",
      school: "evocation",
      class_levels: { "wizard" => 0 },
      components: %w[V S],
      casting_time: "1 standard action",
      range: "close",
      duration: "instantaneous",
      saving_throw: "none",
      spell_resistance: false,
      effects: [{ "type" => "damage", "dice" => "1d3", "damageType" => "cold" }],
      summary: "Ranged touch attack deals 1d3 cold damage."
    )
  end

  let!(:magic_missile) do
    SpellDefinition.create!(
      id: "magic_missile",
      name: "Magic Missile",
      school: "evocation",
      class_levels: { "wizard" => 1 },
      components: %w[V S],
      casting_time: "1 standard action",
      range: "medium",
      duration: "instantaneous",
      saving_throw: "none",
      spell_resistance: true,
      effects: [{ "type" => "damage", "dice" => "1d4+1", "damageType" => "force" }],
      summary: "1 missile (1d4+1 force). Auto-hit."
    )
  end

  let!(:longsword) do
    ItemDefinition.create!(
      id: "longsword",
      name: "Longsword",
      item_type: "weapon",
      category: "martial",
      slot: "none",
      weight: 4,
      cost_gp: 15,
      armor_bonus: 0,
      shield_bonus: 0,
      max_dex_bonus: nil,
      armor_check_penalty: 0,
      arcane_spell_failure: 0,
      speed_30: nil,
      speed_20: nil,
      weapon_category: "martial",
      weapon_type: "melee",
      damage_dice: "1d8",
      critical_range: "19-20/x2",
      damage_type: "slashing",
      range_increment: nil,
      properties: {},
      effects: [],
      summary: "A martial melee weapon."
    )
  end

  before do
    sheet.adventure_sheet_spells.create!(spell_id: ray_of_frost.id, storage_type: "spellbook")
    sheet.adventure_sheet_spells.create!(spell_id: magic_missile.id, storage_type: "spellbook")
    sheet.adventure_sheet_items.create!(item_definition_id: longsword.id, quantity: 1, equipped: true)
  end

  describe ".call" do
    it "builds spell, equipped weapon, and unarmed attack options" do
      options = described_class.call(sheet: sheet, adventure: adventure)

      expect(options).to include(
        include(
          id: "spell:ray_of_frost",
          label: "Ray of Frost",
          attack_mode: "ranged_touch",
          defense_kind: "touch_ac",
          source_type: "spell",
          source_id: "ray_of_frost",
          damage: "1d3",
          damage_type: "cold",
          action_cost: "standard"
        ),
        include(
          id: "longsword",
          label: "Longsword",
          attack_mode: "melee",
          defense_kind: "full_ac",
          source_type: "weapon",
          source_id: "longsword",
          damage: "1d8",
          damage_type: "slashing",
          action_cost: "standard"
        ),
        include(
          id: "unarmed",
          label: "Unarmed Strike",
          attack_mode: "melee",
          defense_kind: "full_ac",
          source_type: "unarmed",
          damage: "1d3",
          damage_type: "bludgeoning",
          action_cost: "standard"
        )
      )
      expect(options.map { |option| option[:id] }).not_to include("spell:magic_missile")
    end

    it "does not expose spells with multiple legal attack profiles yet" do
      produce_flame = SpellDefinition.create!(
        id: "produce_flame",
        name: "Produce Flame",
        school: "evocation",
        class_levels: { "wizard" => 1 },
        components: %w[V S],
        casting_time: "1 standard action",
        range: "personal (or close for ranged touch)",
        duration: "1 min/level",
        saving_throw: "none",
        spell_resistance: false,
        effects: [
          { "type" => "damage", "dice" => "1d6", "damageType" => "fire", "perCasterLevel" => true, "maxDice" => 5 },
          { "type" => "utility", "description" => "Touch attack or throw as ranged touch." }
        ],
        summary: "Flames in hand deal 1d6 + 1/level (max +5) fire. Use as touch or ranged touch."
      )
      sheet.adventure_sheet_spells.create!(spell_id: produce_flame.id, storage_type: "spellbook")

      options = described_class.call(sheet: sheet, adventure: adventure)

      expect(options.map { |option| option[:id] }).not_to include("spell:produce_flame")
    end

    it "filters out attack options when no standard action is available" do
      adventure.update!(combat_context: {
        "action_economy" => {
          "standard_available" => false,
          "move_available" => true,
          "swift_available" => true,
          "full_round_claimed" => false
        }
      })

      expect(described_class.call(sheet: sheet, adventure: adventure)).to eq([])
    end
  end
end
