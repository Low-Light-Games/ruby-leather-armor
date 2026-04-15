# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::AdventurePlay::PipelineMessenger, type: :service do
  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:logger) do
    DungeonMaster::Logging.new(adventure: adventure, user: user).tap do |log|
      log.registry_entry_uuid = SecureRandom.uuid
    end
  end
  let(:messenger) { described_class.new(adventure: adventure, log: logger, user: user) }

  it "persists blocked action results before the initiative prompt" do
    AdventureLoop.create!(
      adventure: adventure,
      registry_entry_uuid: logger.registry_entry_uuid,
      sequence_index: 0,
      raw_action: "approach the goblins stealthily",
      player_intent: "approach the goblins stealthily",
      status: "paused",
      data: { "pipeline_outcome" => "The goblins notice you as you approach." }
    )

    messages = messenger.messages_for(
      action: :awaiting_initiative,
      intent: { intention: "cast Ray of Frost on one of the goblins" },
      creature_data: [{ "name" => "Goblin", "creature_sheet_id" => 1, "initiative" => 12 }],
      mutations: {},
      action_outcomes: ["Ray of Frost did not happen automatically because you were not in the stealthy position that setup required."]
    )

    expect(messages.map(&:message_type)).to eq(%w[action_result initiative_request])
    expect(messages.first.content).to include("did not happen automatically")
    expect(messages.last.content).to include("Roll for initiative!")
  end

  it "persists a visible DM narrative when combat initializes on the player's turn" do
    messages = messenger.messages_for(
      action: :combat_initialized,
      combat_start_message: "Combat begins. Turn order: Player, Goblin. It's your turn."
    )

    expect(messages.map(&:message_type)).to eq(["narrative"])
    expect(messages.first.content).to include("It's your turn")
  end
end
