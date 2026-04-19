# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Utilities::ActiveBuffResolver, type: :service do
  let(:adventure) do
    build_stubbed(:adventure).tap do |a|
      allow(a).to receive(:time_context).and_return(
        "adventure_day" => 1,
        "current_hour"  => 8.0
      )
    end
  end

  let(:sheet) { build_stubbed(:adventure_sheet, level: 5) }

  # ── Helpers ────────────────────────────────────────────────────────────────

  def resolve(source_id:, source_type:, explicit: {})
    described_class.resolve(
      source_id:   source_id,
      source_type: source_type,
      adventure:   adventure,
      sheet:       sheet,
      explicit:    explicit
    )
  end

  def game_hour
    described_class.current_hours(adventure)
  end

  # ── current_hours ──────────────────────────────────────────────────────────

  describe ".current_hours" do
    it "converts day 1 hour 8.0 to 8.0" do
      expect(game_hour).to eq(8.0)
    end

    it "adds 24h per extra adventure day" do
      allow(adventure).to receive(:time_context).and_return(
        "adventure_day" => 3,
        "current_hour"  => 6.0
      )
      expect(described_class.current_hours(adventure)).to eq(54.0)
    end
  end

  # ── compute_duration_hours ─────────────────────────────────────────────────

  describe ".compute_duration_hours" do
    it "returns nil for nil formula" do
      expect(described_class.compute_duration_hours(nil, level: 5)).to be_nil
    end

    it "returns nil for unknown unit" do
      expect(described_class.compute_duration_hours({ "unit" => "centuries", "fixed" => 1 }, level: 5)).to be_nil
    end

    it "handles fixed hours" do
      expect(described_class.compute_duration_hours({ "unit" => "hours", "fixed" => 1 }, level: nil)).to eq(1.0)
    end

    it "handles fixed minutes" do
      expect(described_class.compute_duration_hours({ "unit" => "minutes", "fixed" => 60 }, level: nil)).to be_within(0.001).of(1.0)
    end

    it "handles fixed rounds (10 rounds = 10/600 hours)" do
      expect(described_class.compute_duration_hours({ "unit" => "rounds", "fixed" => 10 }, level: nil))
        .to be_within(0.0001).of(10.0 / 600.0)
    end

    it "handles per_level hours" do
      expect(described_class.compute_duration_hours({ "unit" => "hours", "per_level" => 1 }, level: 5)).to eq(5.0)
    end

    it "handles per_level minutes" do
      expect(described_class.compute_duration_hours({ "unit" => "minutes", "per_level" => 1 }, level: 5))
        .to be_within(0.0001).of(5.0 / 60.0)
    end

    it "returns nil for per_level when level is nil" do
      expect(described_class.compute_duration_hours({ "unit" => "hours", "per_level" => 1 }, level: nil)).to be_nil
    end
  end

  # ── resolve_bonus_value ────────────────────────────────────────────────────

  describe ".resolve_bonus_value" do
    it "returns integer bonus directly" do
      expect(described_class.resolve_bonus_value({ "bonus" => 4 })).to eq(4)
    end

    it "truncates float bonus" do
      expect(described_class.resolve_bonus_value({ "bonus" => 3.9 })).to eq(3)
    end

    it "parses string bonus" do
      expect(described_class.resolve_bonus_value({ "bonus" => "+2" })).to eq(2)
    end

    context "with bonus_formula and no caster_level" do
      let(:formula_effect) { { "bonus_formula" => { "base" => 2, "per_n_cl" => 6, "max" => 5 } } }

      it "falls back to base" do
        expect(described_class.resolve_bonus_value(formula_effect, caster_level: nil)).to eq(2)
      end
    end

    context "with bonus_formula and caster_level" do
      let(:formula) { { "base" => 2, "per_n_cl" => 6, "max" => 5 } }
      let(:effect)  { { "bonus_formula" => formula } }

      it "adds floor(CL / per_n_cl) to base" do
        expect(described_class.resolve_bonus_value(effect, caster_level: 1)).to eq(2)
        expect(described_class.resolve_bonus_value(effect, caster_level: 6)).to eq(3)
        expect(described_class.resolve_bonus_value(effect, caster_level: 12)).to eq(4)
        expect(described_class.resolve_bonus_value(effect, caster_level: 18)).to eq(5)
      end

      it "caps at max" do
        expect(described_class.resolve_bonus_value(effect, caster_level: 30)).to eq(5)
      end

      it "works without a max" do
        no_max = { "base" => 1, "per_n_cl" => 2 }
        expect(described_class.resolve_bonus_value({ "bonus_formula" => no_max }, caster_level: 10)).to eq(6)
      end
    end
  end

  # ── spell resolution ────────────────────────────────────────────────────────

  describe "spell source_type" do
    let(:spell) do
      SpellDefinition.create!(
        id:             "test_mage_armor",
        name:           "Test Mage Armor",
        school:         "abjuration",
        subschool:      nil,
        descriptors:    [],
        class_levels:   { "wizard" => 1 },
        components:     ["V", "S", "F"],
        casting_time:   "1 standard action",
        range:          "touch",
        duration:       "1 hour/level",
        saving_throw:   "will negates (harmless)",
        spell_resistance: false,
        effects:        [{ "type" => "ac_bonus", "bonusType" => "armor", "target" => "ac", "bonus" => 4 }],
        duration_formula: { "unit" => "hours", "per_level" => 1 }
      )
    end

    before { spell }

    it "returns one entry per effect" do
      result = resolve(source_id: "test_mage_armor", source_type: "spell")
      expect(result.length).to eq(1)
    end

    it "sets source to the spell id" do
      result = resolve(source_id: "test_mage_armor", source_type: "spell")
      expect(result.first["source"]).to eq("test_mage_armor")
    end

    it "resolves bonus_type and target" do
      result = resolve(source_id: "test_mage_armor", source_type: "spell")
      expect(result.first["bonus_type"]).to eq("armor")
      expect(result.first["target"]).to eq("ac")
    end

    it "resolves value" do
      result = resolve(source_id: "test_mage_armor", source_type: "spell")
      expect(result.first["value"]).to eq(4)
    end

    it "sets expires_at_game_hours = current + CL hours" do
      # sheet.level = 5, duration = per_level hours, so 5h from 8.0 = 13.0
      result = resolve(source_id: "test_mage_armor", source_type: "spell")
      expect(result.first["expires_at_game_hours"]).to be_within(0.001).of(13.0)
    end

    context "with scaling bonus_formula (shield_of_faith)" do
      let(:scaling_spell) do
        SpellDefinition.create!(
          id:             "test_shield_of_faith",
          name:           "Test Shield of Faith",
          school:         "abjuration",
          subschool:      nil,
          descriptors:    [],
          class_levels:   { "cleric" => 1 },
          components:     ["V", "S", "M"],
          casting_time:   "1 standard action",
          range:          "touch",
          duration:       "1 min/level",
          saving_throw:   "will negates (harmless)",
          spell_resistance: false,
          effects:        [{
            "type"          => "deflection_ac",
            "bonusType"     => "deflection",
            "target"        => "ac",
            "bonus_formula" => { "base" => 2, "per_n_cl" => 6, "max" => 5 }
          }],
          duration_formula: { "unit" => "minutes", "per_level" => 1 }
        )
      end

      before { scaling_spell }

      it "evaluates bonus_formula with caster level 1 → base 2" do
        sheet_l1 = build_stubbed(:adventure_sheet, level: 1)
        result = described_class.resolve(source_id: "test_shield_of_faith", source_type: "spell",
                                         adventure: adventure, sheet: sheet_l1)
        expect(result.first["value"]).to eq(2)
      end

      it "scales at CL 6 → 3" do
        sheet_l6 = build_stubbed(:adventure_sheet, level: 6)
        result = described_class.resolve(source_id: "test_shield_of_faith", source_type: "spell",
                                         adventure: adventure, sheet: sheet_l6)
        expect(result.first["value"]).to eq(3)
      end

      it "caps at max 5" do
        sheet_l20 = build_stubbed(:adventure_sheet, level: 20)
        result = described_class.resolve(source_id: "test_shield_of_faith", source_type: "spell",
                                         adventure: adventure, sheet: sheet_l20)
        expect(result.first["value"]).to eq(5)
      end
    end

    it "returns [] when spell not found" do
      result = resolve(source_id: "nonexistent_spell", source_type: "spell")
      expect(result).to eq([])
    end

    context "with a multi-effect spell" do
      let(:multi_spell) do
        SpellDefinition.create!(
          id:             "test_protection_from_evil",
          name:           "Test Protection from Evil",
          school:         "abjuration",
          subschool:      nil,
          descriptors:    ["good"],
          class_levels:   { "cleric" => 1, "wizard" => 1 },
          components:     ["V", "S", "M"],
          casting_time:   "1 standard action",
          range:          "touch",
          duration:       "1 min/level",
          saving_throw:   "will negates (harmless)",
          spell_resistance: false,
          effects: [
            { "type" => "deflection_ac", "bonusType" => "deflection", "target" => "ac", "bonus" => 2, "applies_vs" => "evil" },
            { "type" => "resistance_bonus", "bonusType" => "resistance", "target" => "saves", "bonus" => 2, "applies_vs" => "evil" }
          ],
          duration_formula: { "unit" => "minutes", "per_level" => 1 }
        )
      end

      before { multi_spell }

      it "returns one entry per effect" do
        result = resolve(source_id: "test_protection_from_evil", source_type: "spell")
        expect(result.length).to eq(2)
      end

      it "preserves conditional metadata in meta field" do
        result = resolve(source_id: "test_protection_from_evil", source_type: "spell")
        expect(result.first["meta"]).to eq({ "applies_vs" => "evil" })
        expect(result.last["meta"]).to eq({ "applies_vs" => "evil" })
      end

      it "stores the saves-target entry for future handlers" do
        result = resolve(source_id: "test_protection_from_evil", source_type: "spell")
        saves_entry = result.find { |e| e["target"] == "saves" }
        expect(saves_entry).not_to be_nil
        expect(saves_entry["value"]).to eq(2)
      end
    end
  end

  # ── item resolution ─────────────────────────────────────────────────────────

  describe "item source_type" do
    let(:item) do
      ItemDefinition.create!(
        id:            "test_potion_of_haste",
        name:          "Test Potion of Haste",
        item_type:     "potion",
        slot:          "none",
        weight:        0.1,
        cost_gp:       750,
        properties:    { "duration_formula" => { "unit" => "rounds", "fixed" => 10 } },
        effects:       [{ "type" => "speed_bonus", "bonusType" => "enhancement", "target" => "speed", "bonus" => 30 }]
      )
    end

    before { item }

    it "resolves speed buff from potion" do
      result = resolve(source_id: "test_potion_of_haste", source_type: "item")
      expect(result.first["target"]).to eq("speed")
      expect(result.first["value"]).to eq(30)
      expect(result.first["bonus_type"]).to eq("enhancement")
    end

    it "converts rounds duration correctly (10 rounds = 10/600 hours)" do
      result = resolve(source_id: "test_potion_of_haste", source_type: "item")
      expected_expiry = 8.0 + 10.0 / 600.0
      expect(result.first["expires_at_game_hours"]).to be_within(0.0001).of(expected_expiry)
    end

    it "does not set expires_at when item has no duration_formula" do
      no_dur = ItemDefinition.create!(
        id: "test_plain_item", name: "Plain", item_type: "gear", slot: "none",
        weight: 1.0, cost_gp: 1, effects: [{ "type" => "ac_bonus", "bonusType" => "natural", "target" => "ac", "bonus" => 1 }]
      )
      result = resolve(source_id: "test_plain_item", source_type: "item")
      expect(result.first["expires_at_game_hours"]).to be_nil
    end

    it "returns [] when item not found" do
      result = resolve(source_id: "nonexistent_potion", source_type: "item")
      expect(result).to eq([])
    end
  end

  # ── class_feature resolution ────────────────────────────────────────────────

  describe "class_feature source_type" do
    let(:explicit) do
      { "bonus_type" => "dodge_bonus", "target" => "ac", "value" => 2, "duration_hours" => 0.0017 }
    end

    it "builds entry from explicit fields" do
      result = resolve(source_id: "fighting_defensively", source_type: "class_feature", explicit: explicit)
      expect(result.length).to eq(1)
      entry = result.first
      expect(entry["source"]).to eq("fighting_defensively")
      expect(entry["bonus_type"]).to eq("dodge_bonus")
      expect(entry["target"]).to eq("ac")
      expect(entry["value"]).to eq(2)
    end

    it "computes expires_at_game_hours from duration_hours" do
      result = resolve(source_id: "fighting_defensively", source_type: "class_feature", explicit: explicit)
      expect(result.first["expires_at_game_hours"]).to be_within(0.0001).of(8.0 + 0.0017)
    end

    it "sets nil expiry when duration_hours absent" do
      result = resolve(source_id: "fighting_defensively", source_type: "class_feature",
                       explicit: explicit.except("duration_hours"))
      expect(result.first["expires_at_game_hours"]).to be_nil
    end

    it "returns [] and logs when required fields are missing" do
      expect(Rails.logger).to receive(:info).with(/missing bonus_type/)
      result = resolve(source_id: "fighting_defensively", source_type: "class_feature", explicit: {})
      expect(result).to eq([])
    end
  end

  # ── unknown source_type ────────────────────────────────────────────────────

  describe "unknown source_type" do
    it "returns [] and logs" do
      expect(Rails.logger).to receive(:info).with(/Unknown source_type/)
      result = resolve(source_id: "foo", source_type: "equipment")
      expect(result).to eq([])
    end
  end
end
