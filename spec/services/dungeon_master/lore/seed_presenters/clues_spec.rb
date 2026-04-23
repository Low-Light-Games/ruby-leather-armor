# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Lore::SeedPresenters::Clues do
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, story: story) }

  it "returns '(none)' when the adventure has no clues" do
    expect(described_class.call(adventure: adventure)).to eq("(none)")
  end

  it "renders one bullet per clue with title, discovery method, difficulty, and indented description" do
    StoryClue.create!(story: story, adventure: nil, source: "manual",
                      title: "Soaked logbook", description: "Pages smeared with ink and salt.",
                      discovery_method: "exploration", difficulty: "moderate")

    expect(described_class.call(adventure: adventure))
      .to eq("- Soaked logbook (discovery: exploration, difficulty: moderate)\n  description: Pages smeared with ink and salt.")
  end

  it "includes both story-level clues and adventure-scoped Embellisher-Expand clues" do
    StoryClue.create!(story: story, adventure: nil, source: "manual",
                      title: "Story clue", description: "Found at camp.",
                      discovery_method: "exploration", difficulty: "moderate")
    StoryClue.create!(story: story, adventure: adventure, source: "embellisher",
                      title: "Expand clue", description: "Whispered in the tavern.",
                      discovery_method: "social", difficulty: "easy")

    output = described_class.call(adventure: adventure)

    expect(output).to include("Story clue")
    expect(output).to include("Expand clue")
  end
end
