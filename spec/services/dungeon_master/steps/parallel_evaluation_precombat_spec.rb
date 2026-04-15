# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::ParallelEvaluation#prepare_canonical_combatants", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story, traversal_context: { "nearby_npcs" => ["Two goblin scouts nearby"] }) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "returns the intent unchanged when warmaster cannot prepare any creatures" do
    intent = {
      intention: "I attack the goblins",
      domain_results: {
        "combat" => {
          transition: "combat_started",
          combatants: ["goblin"]
        }
      }
    }

    allow(adventure).to receive(:combat_active?).and_return(false)
    allow(DungeonMaster::Utilities::Warmaster).to receive(:prepare_from_names!)
      .and_return(status: :no_creatures, creature_data: [])

    result = pipeline.send(:prepare_canonical_combatants, intent)
    expect(result).to eq(intent)
  end
end
