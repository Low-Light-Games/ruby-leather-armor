# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Utilities::CombatTurnCalculator, type: :service do
  let(:player) do
    {
      "name" => "Player", "type" => "player", "initiative" => 10,
      "hp" => 20, "max_hp" => 20, "conditions" => [], "position" => nil
    }
  end

  let(:wolf_a) do
    {
      "name" => "Wolf A", "type" => "npc", "creature_sheet_id" => 1,
      "initiative" => 12, "hp" => 5, "max_hp" => 5, "conditions" => [], "position" => nil
    }
  end

  let(:wolf_b) do
    {
      "name" => "Wolf B", "type" => "npc", "creature_sheet_id" => 2,
      "initiative" => 8, "hp" => 5, "max_hp" => 5, "conditions" => [], "position" => nil
    }
  end

  it "returns NPCs after Player in order, then wraps to earlier initiative next round" do
    ctx = {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Wolf A", "Player", "Wolf B"],
      "participants" => [wolf_a, player, wolf_b]
    }
    out = described_class.call(combat_context: ctx)
    expect(out[:npc_turns].map(&:name)).to eq(["Wolf B", "Wolf A"])
    expect(out[:next_state]["round"]).to eq(2)
    expect(out[:next_state]["current_turn"]).to eq("Player")
  end

  it "when all NPCs are down, ends combat" do
    dead_wolf = wolf_a.merge("hp" => 0)
    ctx = {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Wolf A", "Player"],
      "participants" => [dead_wolf, player]
    }
    out = described_class.call(combat_context: ctx)
    expect(out[:npc_turns]).to be_empty
    expect(out[:next_state]["active"]).to be false
  end

  it "skips NPCs that cannot act" do
    fled = wolf_b.merge("conditions" => ["fled"])
    ctx = {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Wolf A", "Player", "Wolf B"],
      "participants" => [wolf_a, player, fled]
    }
    out = described_class.call(combat_context: ctx)
    expect(out[:npc_turns].map(&:name)).to eq(["Wolf A"])
    expect(out[:next_state]["round"]).to eq(2)
  end
end
