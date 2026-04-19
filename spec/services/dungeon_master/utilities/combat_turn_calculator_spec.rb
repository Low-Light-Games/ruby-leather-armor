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

  it "does not end combat when every NPC is paralyzed (still in the encounter)" do
    paralyzed = wolf_a.merge("conditions" => ["paralyzed"])
    ctx = {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Wolf A", "Player"],
      "participants" => [paralyzed, player]
    }
    out = described_class.call(combat_context: ctx)
    expect(out[:next_state]["active"]).to be true
    expect(out[:npc_turns]).to be_empty
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

  context "when an NPC holds the turn (player acted before their initiative slot)" do
    it "runs pre-player NPCs first, then post-player NPCs, completing the round" do
      # Turn order: Wolf A (12) > Player (10) > Wolf B (8)
      # Wolf A holds the turn — it should have gone before the player.
      ctx = {
        "active" => true,
        "round" => 1,
        "current_turn" => "Wolf A",
        "turn_order" => ["Wolf A", "Player", "Wolf B"],
        "participants" => [wolf_a, player, wolf_b]
      }
      out = described_class.call(combat_context: ctx)
      expect(out[:npc_turns].map(&:name)).to eq(["Wolf A", "Wolf B"])
      expect(out[:next_state]["round"]).to eq(2)
      expect(out[:next_state]["current_turn"]).to eq("Player")
    end

    it "handles multiple pre-player NPCs" do
      orc_high = {
        "name" => "Orc High", "type" => "npc", "creature_sheet_id" => 3,
        "initiative" => 15, "hp" => 9, "max_hp" => 9, "conditions" => [], "position" => nil
      }
      # Turn order: Orc High (15) > Wolf A (12) > Player (10) > Wolf B (8)
      # Orc High holds the turn.
      ctx = {
        "active" => true,
        "round" => 1,
        "current_turn" => "Orc High",
        "turn_order" => ["Orc High", "Wolf A", "Player", "Wolf B"],
        "participants" => [orc_high, wolf_a, player, wolf_b]
      }
      out = described_class.call(combat_context: ctx)
      expect(out[:npc_turns].map(&:name)).to eq(["Orc High", "Wolf A", "Wolf B"])
      expect(out[:next_state]["round"]).to eq(2)
    end

    it "falls back to post-player + wrap when current_turn is not found in turn_order" do
      ctx = {
        "active" => true,
        "round" => 1,
        "current_turn" => "Unknown Creature",
        "turn_order" => ["Wolf A", "Player", "Wolf B"],
        "participants" => [wolf_a, player, wolf_b]
      }
      out = described_class.call(combat_context: ctx)
      expect(out[:npc_turns].map(&:name)).to eq(["Wolf B", "Wolf A"])
      expect(out[:next_state]["round"]).to eq(2)
    end
  end

  context "when combat started from a resolved opener before the player's first combat turn" do
    it "runs only the NPCs before Player and keeps the round on Player's first turn" do
      ctx = {
        "active" => true,
        "round" => 1,
        "current_turn" => "Wolf A",
        "turn_order" => ["Wolf A", "Player", "Wolf B"],
        "participants" => [wolf_a, player, wolf_b]
      }

      out = described_class.call(combat_context: ctx, player_acted_this_round: false)

      expect(out[:npc_turns].map(&:name)).to eq(["Wolf A"])
      expect(out[:next_state]["round"]).to eq(1)
      expect(out[:next_state]["current_turn"]).to eq("Player")
    end
  end
end
