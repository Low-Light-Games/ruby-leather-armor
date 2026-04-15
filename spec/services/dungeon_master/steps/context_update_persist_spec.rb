# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::ContextUpdate#persist_micro_contexts", type: :service do
  include_context "with mocked ai"

  let(:user) { create(:user) }
  let(:story) { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline) { build_pipeline(adventure) }

  it "reads traversal_context from parsed JSON (not bare traversal)" do
    adventure.update!(traversal_context: { "floor" => 1 })
    parsed = { "traversal_context" => { "floor" => 2 } }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    expect(adventure.traversal_context).to include("floor" => 2)
  end

  it "reads combat_context and deep-merges with existing combat" do
    adventure.update!(combat_context: { "active" => true, "round" => 1 })
    parsed = { "combat_context" => { "round" => 2 } }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    expect(adventure.combat_context["active"]).to be true
    expect(adventure.combat_context["round"]).to eq(2)
  end

  it "ignores synthetic combat activation without combat_initialization" do
    adventure.update!(combat_context: {})
    parsed = { "combat_context" => { "active" => true, "round" => 1, "turn_order" => ["Player", "Goblin"] } }

    pipeline.send(:persist_micro_contexts, parsed)
    adventure.reload

    expect(adventure.combat_context).to eq({})
  end

  it "allows combat activation when combat_initialization is present" do
    adventure.update!(combat_context: {})
    parsed = { "combat_context" => { "active" => true, "round" => 1, "turn_order" => ["Player", "Goblin"] } }
    mutations = { "combat_initialization" => parsed["combat_context"] }

    pipeline.send(:persist_micro_contexts, parsed, mutations)
    adventure.reload

    expect(adventure.combat_context["active"]).to be true
    expect(adventure.combat_context["turn_order"]).to eq(["Player", "Goblin"])
  end
end
