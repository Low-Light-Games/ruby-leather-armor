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
    it "resolves attack_roll dc from touch_ac" do
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
      expect(out[:player_rolls].first[:dc]).to eq(creature.reload.derived_stats["touch_ac"].to_i)
      expect(out[:player_rolls].first[:domain]).to eq("combat")
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
