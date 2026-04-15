# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster::Steps::TimeKeeper — effective combat state", type: :service do
  include_context "with mocked ai"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet) { create(:adventure_sheet, adventure: adventure, hp: 4, max_hp: 4, constitution: 10) }
  let(:pipeline) { build_pipeline(adventure) }

  let!(:goblin_a) do
    CreatureSheet.create!(
      adventure: adventure, name: "Goblin A", creature_type: "monster", origin: "template",
      hp: 0, max_hp: 8, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8,
      conditions: ["dead"]
    )
  end

  before do
    adventure.update!(
      combat_context: {
        "active" => true,
        "round" => 1,
        "current_turn" => "Player",
        "turn_order" => ["Player", "Goblin A"],
        "participants" => [
          { "name" => "Player", "type" => "player", "hp" => 4, "max_hp" => 4, "conditions" => [], "initiative" => 14 },
          { "name" => "Goblin A", "type" => "npc", "hp" => 1, "max_hp" => 8, "conditions" => [], "initiative" => 12, "creature_sheet_id" => goblin_a.id }
        ]
      },
      time_context: {
        "current_hour" => 8.0,
        "adventure_day" => 1,
        "light_conditions" => "day",
        "hours_since_last_rest" => 0,
        "hours_since_last_encounter_check" => 0
      }
    )
  end

  it "does not use combat_code when canonical combat has already ended" do
    estimate = pipeline.send(:estimate_time, { intention: "I take a short rest for 1 hour." }, nil)
    expect(estimate[:source]).to eq(:rest_code)
  end

  it "passes combat_active false to the AI time keeper fallback when combat is only stale in context" do
    captured = nil
    allow(pipeline).to receive(:try_journey_estimate).and_return(nil)
    allow(pipeline).to receive(:try_combat_estimate).and_return(nil)
    allow(pipeline).to receive(:try_rest_estimate).and_return(nil)
    allow(pipeline).to receive(:try_take20_estimate).and_return(nil)
    allow(DungeonMaster::PromptRenderer).to receive(:render).and_wrap_original do |orig, template_name, **locals|
      captured = locals if template_name == "time_keeper"
      orig.call(template_name, **locals)
    end
    allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
      instance.instance_variable_set(:@last_parse_status, "success")
      instance.instance_variable_set(:@last_model_used, "test")
      instance.instance_variable_set(:@last_usage, {})
      { "hours_elapsed" => 0.5 }.to_json
    end

    estimate = pipeline.send(:estimate_time, { intention: "I wait quietly." }, {})

    expect(estimate[:source]).to eq(:ai)
    expect(captured[:combat_active]).to eq(false)
  end

  it "still uses combat_code when another hostile remains active" do
    goblin_b = CreatureSheet.create!(
      adventure: adventure, name: "Goblin B", creature_type: "monster", origin: "template",
      hp: 5, max_hp: 8, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8
    )
    adventure.update!(
      combat_context: adventure.combat_context.deep_merge(
        "turn_order" => ["Player", "Goblin A", "Goblin B"],
        "participants" => adventure.combat_context.fetch("participants") + [
          { "name" => "Goblin B", "type" => "npc", "hp" => 5, "max_hp" => 8, "conditions" => [], "initiative" => 10, "creature_sheet_id" => goblin_b.id }
        ]
      )
    )

    estimate = pipeline.send(:estimate_time, { intention: "I take a short rest for 1 hour." }, nil)
    expect(estimate[:source]).to eq(:combat_code)
  end
end
