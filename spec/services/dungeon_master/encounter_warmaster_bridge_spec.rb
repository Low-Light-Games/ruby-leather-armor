# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::EncounterWarmasterBridge, type: :service do
  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story, traversal_context: {}) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:log) { double("log", log!: nil, ai_log!: nil, play_log!: nil) }
  let(:config) { double("config") }
  let(:ai) { double("ai") }
  let(:loop) do
    instance_double(
      AdventureLoop,
      get: nil,
      batch_update!: true
    )
  end

  it "persists pending combat immediately when encounter warmaster awaits initiative" do
    encounter_entry = instance_double(EncounterTableEntry)
    creature_data = [{ name: "Orc 1", creature_sheet_id: 42, initiative: 14 }]
    allow(loop).to receive(:get).with("encounter_entry_id").and_return(123)
    allow(loop).to receive(:get).with("encounter_creatures").and_return([])
    allow(loop).to receive(:get).with("encounter_scene").and_return("An orc patrol approaches.")
    allow(loop).to receive(:get).with("verdict_outcome").and_return("You are spotted.")
    allow(EncounterTableEntry).to receive(:find_by).with(id: 123).and_return(encounter_entry)
    allow(DungeonMaster::Utilities::Warmaster).to receive(:initialize_from_encounter!).and_return(
      { status: :awaiting_initiative, creature_data: creature_data }
    )
    allow(DungeonMaster::Utilities::Warmaster).to receive(:persist_pending_combat!).and_return({})
    allow(described_class).to receive(:reconcile_encounter).and_return("Reconciled encounter.")

    result = described_class.call(
      loop: loop,
      adventure: adventure,
      sheet: sheet,
      log: log,
      config: config,
      ai: ai,
      intent: { intention: "advance carefully" },
      time_result: { encounter: true },
      mutations: {}
    )

    expect(DungeonMaster::Utilities::Warmaster).to have_received(:persist_pending_combat!).with(
      adventure: adventure,
      creature_data: creature_data
    )
    expect(result.payload[:status]).to eq(:awaiting_initiative)
    expect(result.pipeline_outcome).to eq("Reconciled encounter.")
  end
end
