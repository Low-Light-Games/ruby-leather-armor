# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::WorldTurn::NpcActionResult, type: :service do
  it "normalizes npc action result payload shape" do
    result = described_class.new(
      lines: ["Goblin attacks Player: miss."],
      npc_mutations: [{ creature_sheet_id: 5, hp_change: -3 }],
      player_hp_delta: -2,
      battlefield_patches: [{ "op" => "move_token" }]
    )

    expect(result.to_h).to eq(
      lines: ["Goblin attacks Player: miss."],
      npc_muts: [{ creature_sheet_id: 5, hp_change: -3 }],
      player_hp_delta: -2,
      battlefield_patches: [{ "op" => "move_token" }]
    )
  end
end
