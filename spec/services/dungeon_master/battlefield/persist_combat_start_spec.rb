# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Battlefield::PersistCombatStart, type: :service do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet, adventure: adventure,
      constitution: 10, hp: 10, max_hp: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end

  let(:combat_data) do
    {
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
  end

  it "creates battlefield row, battlefield_ref, and action_economy in one transaction" do
    described_class.call(adventure: adventure, combat_data: combat_data, sheet: sheet)
    adventure.reload
    expect(adventure.combat_context["battlefield_ref"]).to include("id", "version", "topology")
    expect(adventure.combat_context["action_economy"]).to be_a(Hash)
    bf = adventure.adventure_battlefields.find(adventure.combat_context["battlefield_ref"]["id"])
    expect(bf).to be_present
    expect(bf.status).to eq("active")
    expect(bf.version).to eq(1)
    expect(bf.tokens).to have_key("player")
  end
end
