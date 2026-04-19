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

  it "raises AiError on version drift and does not apply patches (all environments)" do
    ctx = adventure.combat_context.deep_dup
    ctx["battlefield_ref"] = ctx["battlefield_ref"].merge("version" => 0)
    adventure.update!(combat_context: ctx)

    expect do
      described_class.call(
        adventure: adventure.reload,
        patches: [{ "op" => "move_token", "id" => "player", "x" => 99, "y" => 99 }],
        log: nil
      )
    end.to raise_error(DungeonMaster::AiError, /version drift/)

    adventure.reload
    bf = adventure.adventure_battlefields.find(adventure.combat_context["battlefield_ref"]["id"])
    expect(bf.tokens["player"]["x"]).not_to eq(99)
  end

  it "raises AiError on unknown patch op" do
    expect do
      described_class.call(
        adventure: adventure,
        patches: [{ "op" => "teleport_all", "id" => "player" }],
        log: nil
      )
    end.to raise_error(DungeonMaster::AiError, /unknown op/)
  end

  it "raises AiError when set_cells uses a disallowed attribute" do
    expect do
      described_class.call(
        adventure: adventure,
        patches: [{
          "op" => "set_cells",
          "cells" => [{ "x" => 1, "y" => 2, "custom_hazard" => true }]
        }],
        log: nil
      )
    end.to raise_error(DungeonMaster::AiError, /disallowed cell attribute/)
  end

  it "applies set_cells with allowlisted attributes" do
    described_class.call(
      adventure: adventure,
      patches: [{
        "op" => "set_cells",
        "cells" => [{ "x" => 3, "y" => 4, "terrain" => "rubble", "cover" => "partial" }]
      }],
      log: nil
    )
    adventure.reload
    bf = adventure.adventure_battlefields.find(adventure.combat_context["battlefield_ref"]["id"])
    expect(bf.world["cells"]["3,4"]).to eq("terrain" => "rubble", "cover" => "partial")
  end

  it "keeps other combat_context keys from the locked snapshot when syncing battlefield_ref" do
    ctx = adventure.combat_context.deep_dup
    ctx["action_economy"] = { "move_available" => false, "standard_available" => true }
    adventure.update!(combat_context: ctx)

    described_class.call(
      adventure: adventure.reload,
      patches: [{ "op" => "move_token", "id" => "player", "x" => 12, "y" => 14 }],
      log: nil
    )
    adventure.reload
    expect(adventure.combat_context["action_economy"]).to eq(
      "move_available" => false, "standard_available" => true
    )
  end
end
