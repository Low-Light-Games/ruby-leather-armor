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

  it "archives a stray active row whose tokens do not match participants, then creates a matching battlefield" do
    adventure.adventure_battlefields.create!(
      adventure: adventure,
      status: "active",
      topology: "square",
      world: { "cells" => {} },
      tokens: { "player" => { "label" => "Player", "x" => 0, "y" => 0 } },
      viewport: { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 },
      version: 1
    )

    adventure.update!(combat_context: {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => %w[Player Goblin],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 15, "conditions" => [] },
        { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 5, "initiative" => 10, "conditions" => [] }
      ],
      "terrain_notes" => nil,
    })

    described_class.call(adventure: adventure.reload, sheet: sheet)
    adventure.reload
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
    expect(adventure.combat_context["battlefield_ref"]).to be_present
    bf = adventure.adventure_battlefields.find(adventure.combat_context["battlefield_ref"]["id"])
    expect(bf.tokens.keys.sort).to eq(%w[player token_1_goblin].sort)
  end

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
    })

    described_class.call(adventure: adventure.reload, sheet: sheet)
    adventure.reload
    expect(adventure.combat_context["battlefield_ref"]).to be_present
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
  end

  it "reattaches to an existing active row when battlefield_ref is missing" do
    # Token ids must match PersistCombatStart.build_tokens_from_participants for these participants.
    bf = adventure.adventure_battlefields.create!(
      adventure: adventure,
      status: "active",
      topology: "square",
      world: { "cells" => {} },
      tokens: {
        "player" => { "label" => "Player", "x" => 0, "y" => 0 },
        "token_1_goblin" => { "label" => "Goblin", "x" => 2, "y" => 0 }
      },
      viewport: { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 },
      version: 1
    )

    adventure.update!(combat_context: {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player", "Goblin"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 15, "conditions" => [] },
        { "name" => "Goblin", "type" => "npc", "hp" => 5, "max_hp" => 5, "initiative" => 10, "conditions" => [] }
      ],
      "terrain_notes" => nil,
    })

    described_class.call(adventure: adventure.reload, sheet: sheet)
    adventure.reload
    expect(adventure.combat_context["battlefield_ref"]["id"]).to eq(bf.id)
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
  end

  it "dedupes multiple active rows, keeps oldest, and attaches ref" do
    bf1 = adventure.adventure_battlefields.create!(
      adventure: adventure,
      status: "active",
      topology: "square",
      world: { "cells" => {} },
      tokens: { "player" => { "label" => "Player", "x" => 0, "y" => 0 } },
      viewport: { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 },
      version: 1
    )
    adventure.adventure_battlefields.create!(
      adventure: adventure,
      status: "active",
      topology: "square",
      world: { "cells" => {} },
      tokens: { "player" => { "label" => "Player", "x" => 99, "y" => 99 } },
      viewport: { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 },
      version: 1
    )

    adventure.update!(combat_context: {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 10, "conditions" => [] }
      ],
      "terrain_notes" => nil,
    })

    described_class.call(adventure: adventure.reload, sheet: sheet)
    adventure.reload
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
    expect(adventure.adventure_battlefields.where(status: "archived").count).to eq(1)
    expect(adventure.combat_context["battlefield_ref"]["id"]).to eq(bf1.id)
  end

  it "dedupes duplicate active rows even when battlefield_ref already points at an active row" do
    combat_data = {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 10, "conditions" => [] }
      ],
      "terrain_notes" => nil,
    }
    DungeonMaster::Battlefield::PersistCombatStart.call(adventure: adventure, combat_data: combat_data, sheet: sheet)
    adventure.reload
    target_id = adventure.combat_context["battlefield_ref"]["id"]

    adventure.adventure_battlefields.create!(
      adventure: adventure,
      status: "active",
      topology: "square",
      world: { "cells" => {} },
      tokens: { "player" => { "label" => "Player", "x" => 0, "y" => 0 } },
      viewport: { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 },
      version: 1
    )

    described_class.call(adventure: adventure.reload, sheet: sheet)
    adventure.reload
    expect(adventure.adventure_battlefields.where(status: "active").count).to eq(1)
    expect(adventure.adventure_battlefields.where(status: "archived").count).to eq(1)
    expect(adventure.combat_context["battlefield_ref"]["id"]).to eq(target_id)
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
