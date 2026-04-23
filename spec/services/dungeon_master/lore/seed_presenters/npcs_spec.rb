# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Lore::SeedPresenters::Npcs do
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, story: story) }

  it "returns '(none)' when the adventure has no NPCs" do
    expect(described_class.call(adventure: adventure)).to eq("(none)")
  end

  it "renders one bullet per NPC with name, role, and attitude" do
    StoryNpc.create!(story: story, adventure: nil, source: "manual",
                     name: "Captain Rook", role: "informant", attitude: "friendly")

    expect(described_class.call(adventure: adventure))
      .to eq("- Captain Rook (role: informant, attitude: friendly)")
  end

  it "appends an indented description line only when description is present" do
    StoryNpc.create!(story: story, adventure: nil, source: "manual",
                     name: "Gerta", role: "merchant", attitude: "indifferent",
                     description: "A weathered old salt.")
    StoryNpc.create!(story: story, adventure: nil, source: "manual",
                     name: "Silent Hal", role: "antagonist", attitude: "unfriendly")

    output = described_class.call(adventure: adventure)

    expect(output).to include("- Gerta (role: merchant, attitude: indifferent)\n  description: A weathered old salt.")
    expect(output).to include("- Silent Hal (role: antagonist, attitude: unfriendly)")
    expect(output).not_to match(/Silent Hal.*\n\s+description:/m)
  end

  it "includes both story-level NPCs and adventure-scoped Embellisher-Expand NPCs" do
    StoryNpc.create!(story: story, adventure: nil, source: "manual",
                     name: "Story NPC", role: "quest_giver", attitude: "friendly")
    StoryNpc.create!(story: story, adventure: adventure, source: "embellisher",
                     name: "Expand NPC", role: "antagonist", attitude: "unfriendly")

    output = described_class.call(adventure: adventure)

    expect(output).to include("Story NPC")
    expect(output).to include("Expand NPC")
  end
end
