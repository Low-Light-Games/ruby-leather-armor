# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::WorldTurn::NpcActionResolver, type: :service do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:player_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 12, max_hp: 12, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1).tap(&:recompute_derived_stats!)
  end
  let(:npc) do
    DungeonMaster::Utilities::Combatant.new(
      name: "Goblin 2",
      creature_sheet_id: 123,
      type: "npc",
      initiative: 12,
      hp: 6,
      max_hp: 6,
      conditions: []
    )
  end

  it "uses CombatDice for attack and damage rolls against the player" do
    allow(DungeonMaster::Rolls::CombatDice).to receive(:d20_attack_vs_ac)
      .with(modifier: 2, ac: player_sheet.derived_stats.fetch("ac").to_i)
      .and_return(d20: 20, total: 22, hit: true)
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression)
      .with("1d6")
      .and_return(6)

    result = described_class.resolve(
      npc: npc,
      parsed: { action: "attack", target: "Player", attack_modifier: 2, damage_dice: "1d6" },
      combat_ctx: { "participants" => [] },
      player_sheet: player_sheet,
      adventure: adventure
    )

    expect(result[:lines]).to eq(["Goblin 2 attacks Player: 20+2=22 vs AC #{player_sheet.derived_stats.fetch("ac").to_i} — HIT for 6."])
    expect(result[:player_hp_delta]).to eq(-6)
  end
end
