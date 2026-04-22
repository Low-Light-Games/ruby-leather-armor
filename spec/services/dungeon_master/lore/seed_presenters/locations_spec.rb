# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Lore::SeedPresenters::Locations do
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, story: story) }

  it "returns '(none)' when the story has no locations" do
    expect(described_class.call(adventure: adventure)).to eq("(none)")
  end

  it "returns '(none)' when the adventure has no story (defensive nil-guard)" do
    orphan = build_stubbed(:adventure, story: nil)
    expect(described_class.call(adventure: orphan)).to eq("(none)")
  end

  it "renders one bullet per location with only the name on the header line" do
    story.story_locations.create!(name: "The Wreckage")

    expect(described_class.call(adventure: adventure)).to eq("- The Wreckage")
  end

  it "appends an indented description line only when description is present" do
    story.story_locations.create!(name: "The Wreckage", description: "A splintered raft.")
    story.story_locations.create!(name: "Open Water")

    output = described_class.call(adventure: adventure)

    expect(output).to include("- The Wreckage\n  description: A splintered raft.")
    expect(output).to include("- Open Water")
    expect(output).not_to match(/Open Water.*\n\s+description:/m)
  end
end
