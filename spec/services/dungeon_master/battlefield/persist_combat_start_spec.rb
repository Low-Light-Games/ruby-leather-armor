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

  it "archives the prior active row and creates a fresh battlefield on each combat start" do
    described_class.call(adventure: adventure, combat_data: combat_data, sheet: sheet)
    first_id = adventure.reload.combat_context["battlefield_ref"]["id"]

    described_class.call(adventure: adventure.reload, combat_data: combat_data, sheet: sheet)
    adventure.reload
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
    expect(adventure.combat_context["battlefield_ref"]["id"]).not_to eq(first_id)
    expect(adventure.adventure_battlefields.find(first_id).status).to eq("archived")
  end

  it "archives a stale active row when participant token set changes, then creates a fresh battlefield" do
    described_class.call(adventure: adventure, combat_data: combat_data, sheet: sheet)
    stale_id = adventure.reload.combat_context["battlefield_ref"]["id"]

    two_party = combat_data.merge(
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 10, "conditions" => [] },
        { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 5, "initiative" => 8, "conditions" => [] }
      ],
      "turn_order" => %w[Player Goblin]
    )
    described_class.call(adventure: adventure.reload, combat_data: two_party, sheet: sheet)
    adventure.reload

    expect(adventure.adventure_battlefields.find(stale_id).status).to eq("archived")
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
    expect(adventure.combat_context["battlefield_ref"]["id"]).not_to eq(stale_id)
  end
end
