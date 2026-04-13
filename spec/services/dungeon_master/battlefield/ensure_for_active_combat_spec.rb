# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Battlefield::EnsureForActiveCombat, type: :service do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet, adventure: adventure,
      constitution: 10, hp: 10, max_hp: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end

  before { sheet }

  it "creates battlefield_ref when combat is active but ref is missing" do
    adventure.update!(combat_context: {
      "active" => true,
      "round" => 2,
      "current_turn" => "Player",
      "turn_order" => ["Player", "Goblin"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 15, "conditions" => [] },
        { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 5, "initiative" => 10, "conditions" => [] }
      ],
      "terrain_notes" => nil,
      "active_effects" => []
    })

    described_class.call(adventure: adventure.reload, sheet: sheet)
    adventure.reload
    expect(adventure.combat_context["battlefield_ref"]).to be_present
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
  end

  it "is a no-op when an active battlefield row already exists" do
    combat_data = {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 10, "conditions" => [] }
      ],
      "terrain_notes" => nil,
      "active_effects" => []
    }
    DungeonMaster::Battlefield::PersistCombatStart.call(adventure: adventure, combat_data: combat_data, sheet: sheet)
    adventure.reload
    id_before = adventure.combat_context["battlefield_ref"]["id"]

    described_class.call(adventure: adventure, sheet: sheet)
    adventure.reload
    expect(adventure.combat_context["battlefield_ref"]["id"]).to eq(id_before)
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
  end
end
