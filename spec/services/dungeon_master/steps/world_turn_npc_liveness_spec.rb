# frozen_string_literal: true

require "rails_helper"

# Guard: an NPC that reaches hp=0 earlier in the same round must be skipped,
# not resolved a second time.  Covers the per-iteration liveness re-check added
# after the pre-built acting_npcs list was identified as a gap.
RSpec.describe "DungeonMaster::Steps::WorldTurn — per-iteration NPC liveness", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end
  let(:pipeline) { build_pipeline(adventure) }

  # Two creature sheets; the second (lower initiative) will be at 0 hp when its turn arrives.
  let!(:goblin_a) do
    CreatureSheet.create!(
      adventure: adventure, name: "Goblin A", creature_type: "monster", origin: "template",
      hp: 5, max_hp: 5, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8)
  end
  let!(:goblin_b) do
    CreatureSheet.create!(
      adventure: adventure, name: "Goblin B", creature_type: "monster", origin: "template",
      hp: 0, max_hp: 5, constitution: 10,
      strength: 10, dexterity: 8, intelligence: 6, wisdom: 8, charisma: 8)
  end

  it "skips an NPC whose creature_sheet HP is 0 at resolve time, even if it was in the acting list" do
    # Turn order: Player acted, then Goblin A, then Goblin B.
    # current_turn = "Player" is required for CombatTurnCalculator to return NPC turns.
    # Goblin B has HP=5 in the combat_context snapshot (so it passes can_act? and is included
    # in acting_npcs), but the DB creature_sheet row already has hp=0 — simulating a case where
    # an intermediate reaction or patch zeroed out Goblin B between the AI fan_out and resolution.
    adventure.update!(combat_context: {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player", "Goblin A", "Goblin B"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10,
          "initiative" => 20, "conditions" => [] },
        { "name" => "Goblin A", "type" => "npc", "hp" => 5, "max_hp" => 5,
          "initiative" => 15, "conditions" => [], "creature_sheet_id" => goblin_a.id },
        { "name" => "Goblin B", "type" => "npc", "hp" => 5, "max_hp" => 5,
          "initiative" => 10, "conditions" => [], "creature_sheet_id" => goblin_b.id }
      ],
      "terrain_notes" => nil,
    })

    resolved_names = []
    # Stub resolve to track which NPCs were attempted without needing full derived_stats.
    allow(DungeonMaster::WorldTurn::NpcActionResolver).to receive(:resolve) do |**kwargs|
      resolved_names << kwargs[:npc].name
      { lines: ["#{kwargs[:npc].name} acts."], player_hp_delta: 0, npc_muts: [], battlefield_patches: [] }
    end

    pipeline.send(:run_world_turn, {
      status: :resolved,
      intent: { intention: "defend", affected_contexts: [], macro_significant: false, domain_results: {} },
      mutations: {}
    })

    expect(resolved_names).to include("Goblin A")
    expect(resolved_names).not_to include("Goblin B")
  end

  it "does not raise when a surviving player is checked for combat end after an NPC hit" do
    goblin_b.update!(hp: 5, max_hp: 5, dexterity: 8)

    adventure.update!(combat_context: {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player", "Goblin A"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10,
          "initiative" => 20, "conditions" => [] },
        { "name" => "Goblin A", "type" => "npc", "hp" => 5, "max_hp" => 5,
          "initiative" => 15, "conditions" => [], "creature_sheet_id" => goblin_a.id }
      ],
      "terrain_notes" => nil
    })

    allow(pipeline).to receive(:request_npc_actions).and_return([["npc_action_0"], {}])
    allow(pipeline).to receive(:evaluator_fan_out_result!).and_return({
      "parsed_response" => {
        "action" => "attack",
        "target" => "Player",
        "attack_modifier" => 1,
        "damage_dice" => "1d6+1",
        "battlefield_patches" => []
      }
    })
    allow(DungeonMaster::WorldTurn::NpcActionResolver).to receive(:resolve).and_return({
      lines: ["Goblin A attacks Player: hit for 3."],
      player_hp_delta: -3,
      npc_muts: [],
      battlefield_patches: []
    })

    expect do
      pipeline.send(:run_world_turn, {
        status: :resolved,
        intent: { intention: "cast Ray of Frost", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
        mutations: {}
      })
    end.not_to raise_error
  end

  it "raises instead of silently skipping an acting npc whose participant identity is missing" do
    adventure.update!(combat_context: {
      "active" => true,
      "round" => 1,
      "current_turn" => "Player",
      "turn_order" => ["Player", "Goblin A"],
      "participants" => [
        { "name" => "Player", "type" => "player", "hp" => 10, "max_hp" => 10, "initiative" => 20, "conditions" => [] },
        { "name" => "Goblin A", "type" => "npc", "hp" => 5, "max_hp" => 5, "initiative" => 15, "conditions" => [] }
      ],
      "terrain_notes" => nil
    })

    expect do
      pipeline.send(:run_world_turn, {
        status: :resolved,
        intent: { intention: "cast Ray of Frost", affected_contexts: ["combat"], macro_significant: false, domain_results: {} },
        mutations: {}
      })
    end.to raise_error(DungeonMaster::AiError, /missing creature_sheet_id/i)
  end
end
