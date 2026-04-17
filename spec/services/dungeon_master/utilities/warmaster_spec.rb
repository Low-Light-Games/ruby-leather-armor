# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Utilities::Warmaster, type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure, level: 1) }
  let(:log) { OpenStruct.new(log!: nil, play_log!: nil) }
  let(:config) { instance_double(DmConfig, get: "template") }
  let(:ai) { instance_double(DungeonMaster::AiClient) }

  it "rolls bestiary/template hp in code rather than taking AI hp" do
    allow(described_class).to receive(:roll_hp_static).and_return(9)

    creature = described_class.send(
      :create_from_template_static,
      described_class::Context.new(adventure: adventure, sheet: sheet, log: log, config: config, ai: ai),
      "Goblin",
      1
    )

    expect(described_class).to have_received(:roll_hp_static)
    expect(creature.hp).to eq(9)
    expect(creature.max_hp).to eq(9)
  end
end
