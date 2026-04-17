# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::AdventureLoopResolution social scene routing", type: :service do
  include_context "with mocked ai"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "keeps pure social expansion on the world-only gate without capability check" do
    intent = {
      intention: "I haggle with the merchant over the relic.",
      affected_contexts: ["social"],
      expand_scene: true,
      macro_significant: false,
      domain_results: {
        "social" => { domain: "social", affected: true, expand_scene: true }
      }
    }

    allow(pipeline).to receive(:run_parallel_evaluation).and_return([intent, []])
    allow(pipeline).to receive(:skip_world_sanity_for_privileged_player?).and_return(false)
    allow(pipeline).to receive(:run_world_consistency_check).with(intent).and_return({ consistent: true })
    allow(pipeline).to receive(:resolve_social_scene).with(intent).and_return(status: :social_scene, intent: intent)
    expect(pipeline).not_to receive(:run_capability_check)
    expect(pipeline).not_to receive(:run_sanity_gate_fan_out)

    result = pipeline.send(:resolve, intent[:intention])

    expect(result[:status]).to eq(:social_scene)
  end
end
