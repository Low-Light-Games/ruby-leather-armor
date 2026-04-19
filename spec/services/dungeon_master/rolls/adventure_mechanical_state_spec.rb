# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Rolls::AdventureMechanicalState, type: :service do
  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end
  let(:log) { instance_double(DungeonMaster::Logging, log!: nil) }

  it "ignores malformed non-hash creature_data rows when auto-finalizing initiative" do
    init_msg = create(:adventure_message,
      adventure: adventure,
      role: "dm",
      message_type: "initiative_request",
      metadata: { "creature_data" => ["Goblin", { "name" => "Goblin 2", "creature_sheet_id" => 123, "initiative" => 9 }] })
    create(:adventure_message,
      adventure: adventure,
      role: "player",
      message_type: "narrative",
      content: "I do something else",
      created_at: init_msg.created_at + 1.second)

    allow(DungeonMaster::Utilities::Warmaster).to receive(:auto_roll_player_initiative).and_return(12)
    allow(DungeonMaster::Utilities::Warmaster).to receive(:compute_combat_initialization).and_return({ "active" => true, "participants" => [] })
    allow(DungeonMaster::Battlefield::PersistCombatStart).to receive(:call)

    expect {
      described_class.auto_finalize_pending_initiative!(adventure: adventure, sheet: sheet, log: log)
    }.not_to raise_error

    expect(DungeonMaster::Utilities::Warmaster).to have_received(:compute_combat_initialization).with(
      adventure: adventure,
      player_sheet: sheet,
      creature_data: [hash_including(name: "Goblin 2", creature_sheet_id: 123, initiative: 9)],
      player_initiative: 12
    )
  end

  it "does not auto-finalize an initiative request that was already fulfilled" do
    init_msg = create(:adventure_message,
      adventure: adventure,
      role: "dm",
      message_type: "initiative_request",
      metadata: { "creature_data" => [{ "name" => "Goblin", "creature_sheet_id" => 123, "initiative" => 9 }] })
    create(:adventure_message,
      adventure: adventure,
      role: "player",
      message_type: "initiative_result",
      content: "Initiative: 20",
      metadata: { "initiative" => 20 },
      created_at: init_msg.created_at + 1.second)
    create(:adventure_message,
      adventure: adventure,
      role: "player",
      message_type: "narrative",
      content: "I look around",
      created_at: init_msg.created_at + 2.seconds)

    allow(DungeonMaster::Utilities::Warmaster).to receive(:auto_roll_player_initiative)
    allow(DungeonMaster::Utilities::Warmaster).to receive(:compute_combat_initialization)
    allow(DungeonMaster::Battlefield::PersistCombatStart).to receive(:call)

    described_class.auto_finalize_pending_initiative!(adventure: adventure, sheet: sheet, log: log)

    expect(DungeonMaster::Utilities::Warmaster).not_to have_received(:auto_roll_player_initiative)
    expect(DungeonMaster::Utilities::Warmaster).not_to have_received(:compute_combat_initialization)
    expect(DungeonMaster::Battlefield::PersistCombatStart).not_to have_received(:call)
  end
end
