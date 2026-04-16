# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Steps::Phases::CombatMechanicResolution do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet, adventure: adventure, character_class: "wizard", level: 3).tap(&:recompute_derived_stats!)
  end

  let(:creature) do
    adventure.creature_sheets.create!(
      name: "Goblin",
      creature_type: "monster",
      origin: "template",
      strength: 10, dexterity: 14, constitution: 10,
      intelligence: 8, wisdom: 10, charisma: 8,
      level: 2, hp: 6, max_hp: 6,
      derived_stats: { "ac" => 15, "bab" => 1, "speed" => 30 }
    ).tap(&:recompute_derived_stats!)
  end

  let(:combat_ctx) do
    { "participants" => [{ "name" => "Goblin", "creature_sheet_id" => creature.id }] }
  end

  before do
    adventure.update!(combat_context: combat_ctx)
  end

  describe ".call" do
    it "resolves attack_roll dc from touch_ac and omits defense_kind from output" do
      parsed = {
        player_rolls: [
          {
            type: "attack_roll",
            target: "Goblin",
            defense_kind: "touch_ac",
            description: "Ray"
          }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "test"
      }

      out = described_class.call(
        parsed: parsed,
        domain: "combat",
        adventure: adventure,
        sheet: sheet
      )

      expect(out[:player_rolls].size).to eq(1)
      roll = out[:player_rolls].first
      expect(roll[:dc]).to eq(creature.reload.derived_stats["touch_ac"].to_i)
      expect(roll[:domain]).to eq("combat")
      expect(roll).not_to have_key(:defense_kind)
    end

    it "resolves full_ac from creature sheet" do
      parsed = {
        player_rolls: [
          { type: "attack_roll", target: "Goblin", defense_kind: "full_ac", description: "arrow" }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      out = described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      expect(out[:player_rolls].first[:dc]).to eq(creature.reload.derived_stats["ac"].to_i)
    end

    it "raises when attack_roll includes dc from the model" do
      parsed = {
        player_rolls: [
          { type: "attack_roll", target: "Goblin", defense_kind: "full_ac", dc: 10, description: "bad" }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      expect {
        described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      }.to raise_error(DungeonMaster::CombatMechanicResolutionError, /attack_roll must not include dc/)
    end

    it "raises when saving_throw includes dc from the model" do
      parsed = {
        player_rolls: [
          { type: "saving_throw", save: "ref", dc: 15, description: "bad", dc_formula: { kind: "spell_dc" } }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      expect {
        described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      }.to raise_error(DungeonMaster::CombatMechanicResolutionError, /saving_throw must not include dc/)
    end

    it "raises for unsupported player_roll type" do
      parsed = {
        player_rolls: [
          { type: "skill_check", skill: "Perception", dc: 10, description: "nope" }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      expect {
        described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      }.to raise_error(DungeonMaster::CombatMechanicResolutionError, /unsupported player_roll type/)
    end

    it "raises when target is not in combat participants" do
      parsed = {
        player_rolls: [
          { type: "attack_roll", target: "Orc", defense_kind: "full_ac", description: "hit" }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      expect {
        described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      }.to raise_error(DungeonMaster::CombatMechanicResolutionError, /not in combat participants/)
    end

    it "resolves spell_dc using the spell list's class (multiclass: wizard spell uses Intelligence)" do
      spell = SpellDefinition.create!(
        id: "cmr_spec_mc_fireball",
        name: "CombatMechSpecFireball",
        school: "evocation",
        class_levels: { "wizard" => 3 },
        created_at: Time.current,
        updated_at: Time.current
      )

      mc_sheet = create(:adventure_sheet,
        adventure: adventure,
        character_class: "Cleric 5 / Wizard 3",
        level: 8,
        intelligence: 18,
        wisdom: 12
      ).tap(&:recompute_derived_stats!)

      parsed = {
        player_rolls: [
          {
            type: "saving_throw",
            save: "ref",
            description: "Fireball",
            dc_formula: { kind: "spell_dc", spell_name: spell.name, caster: "player" }
          }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      out = described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: mc_sheet)
      int_mod = ((18 - 10) / 2).floor # +4
      expect(out[:player_rolls].first[:dc]).to eq(10 + 3 + int_mod)

      spell.destroy!
    end

    it "resolves ability_dc half_hd_plus_ability from origin creature" do
      parsed = {
        player_rolls: [
          {
            type: "saving_throw",
            save: "fort",
            description: "stink",
            dc_formula: {
              kind: "ability_dc",
              pattern: "half_hd_plus_ability",
              ability: "constitution",
              origin_target: "Goblin"
            }
          }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      out = described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      con_mod = ((creature.constitution.to_i - 10) / 2).floor
      hd = creature.level.to_i
      expect(out[:player_rolls].first[:dc]).to eq(10 + (hd / 2) + con_mod)
    end

    it "raises for unsupported dc_formula kind" do
      parsed = {
        player_rolls: [
          {
            type: "saving_throw",
            save: "will",
            dc_formula: { kind: "fixed", ref: "trap" },
            description: "x"
          }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      expect {
        described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      }.to raise_error(DungeonMaster::CombatMechanicResolutionError, /unsupported dc_formula.kind/)
    end

    it "raises for non-player spell_dc caster" do
      spell = SpellDefinition.create!(
        id: "cmr_spec_npc_spell",
        name: "CombatMechSpecHold",
        school: "enchantment",
        class_levels: { "wizard" => 2 },
        created_at: Time.current,
        updated_at: Time.current
      )

      parsed = {
        player_rolls: [
          {
            type: "saving_throw",
            save: "will",
            description: "Hold",
            dc_formula: { kind: "spell_dc", spell_name: spell.name, caster: "Goblin" }
          }
        ],
        npc_actions: [],
        consequences: [],
        mechanical_summary: "x"
      }

      expect {
        described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet)
      }.to raise_error(DungeonMaster::CombatMechanicResolutionError, /spell_dc only supports player-cast/)

      spell.destroy!
    end

    it "drops non-AoO npc_actions" do
      parsed = {
        player_rolls: [],
        npc_actions: [
          { action: "attack", actor: "Goblin", target: "player", modifier: 3, damage: "1d6" }
        ],
        consequences: [],
        mechanical_summary: "x"
      }

      log = instance_double(DungeonMaster::Logging, play_log!: nil)
      out = described_class.call(parsed: parsed, domain: "combat", adventure: adventure, sheet: sheet, log: log)
      expect(out[:npc_actions]).to be_empty
    end
  end
end
