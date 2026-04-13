# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Battlefield::ApplyPatches, type: :service do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet, adventure: adventure,
      constitution: 10, hp: 10, max_hp: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end

  before do
    DungeonMaster::Battlefield::PersistCombatStart.call(
      adventure: adventure,
      combat_data: {
        "active" => true,
        "round" => 1,
        "current_turn" => "Player",
        "turn_order" => ["Player"],
        "participants" => [
          { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 10, "conditions" => [] }
        ],
        "terrain_notes" => nil,
        "active_effects" => []
      },
      sheet: sheet
    )
    adventure.reload
  end

  it "moves a token and bumps version in combat_context" do
    v0 = adventure.combat_context["battlefield_ref"]["version"]
    described_class.call(
      adventure: adventure,
      patches: [{ "op" => "move_token", "id" => "player", "x" => 25, "y" => 30 }],
      log: nil
    )
    adventure.reload
    bf = adventure.adventure_battlefields.find(adventure.combat_context["battlefield_ref"]["id"])
    expect(bf.version).to eq(v0 + 1)
    expect(bf.tokens["player"]["x"]).to eq(25)
    expect(bf.tokens["player"]["y"]).to eq(30)
    expect(adventure.combat_context["battlefield_ref"]["version"]).to eq(bf.version)
  end
end
