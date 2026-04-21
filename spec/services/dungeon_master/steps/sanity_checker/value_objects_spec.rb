# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::SanityChecker value objects", type: :service do
  it "serializes capability check results to stable hashes" do
    payload = DungeonMaster::Steps::SanityChecker::CapabilityCheckResult.new(
      allowed: false,
      reason: "missing spell"
    ).to_h

    expect(payload).to eq(allowed: false, reason: "missing spell")
  end

  it "serializes world consistency results to stable hashes" do
    payload = DungeonMaster::Steps::SanityChecker::WorldConsistencyResult.new(
      consistent: true,
      reason: nil,
      dm_message: "All clear.",
      referenced_entities: ["Goblin"]
    ).to_h

    expect(payload).to eq(
      consistent: true,
      reason: nil,
      dm_message: "All clear.",
      referenced_entities: ["Goblin"]
    )
  end
end
