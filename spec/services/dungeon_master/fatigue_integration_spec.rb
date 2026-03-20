require "rails_helper"

RSpec.describe "Fatigue condition integration", type: :service do
  include_context "with mocked ai"

  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure).tap(&:recompute_derived_stats!) }

  describe DungeonMaster::Utilities::GameClock do
    describe ".check_thresholds" do
      it "returns no fatigue alert below 16 hours" do
        ctx = { "hours_since_last_rest" => 15.9 }
        expect(described_class.check_thresholds(ctx)).to be_empty
      end

      it "returns fatigued at 16 hours" do
        ctx = { "hours_since_last_rest" => 16.0 }
        alerts = described_class.check_thresholds(ctx)
        expect(alerts.size).to eq(1)
        expect(alerts.first).to include(type: :fatigue, condition: "fatigued")
      end

      it "returns exhausted at 32 hours" do
        ctx = { "hours_since_last_rest" => 32.0 }
        alerts = described_class.check_thresholds(ctx)
        expect(alerts.first).to include(type: :fatigue, condition: "exhausted")
      end

      it "returns fatigued between 16 and 32 hours" do
        ctx = { "hours_since_last_rest" => 24.0 }
        alerts = described_class.check_thresholds(ctx)
        expect(alerts.first[:condition]).to eq("fatigued")
      end
    end

    describe ".advance_clock! with rest" do
      before do
        adventure.update!(time_context: {
          "current_hour" => 22,
          "adventure_day" => 1,
          "hours_since_last_rest" => 18,
          "hours_since_last_encounter_check" => 0
        })
      end

      it "sets rest_clears_fatigue flag on rest action" do
        intent = { intention: "I take a long rest at the inn." }
        ctx = described_class.advance_clock!(adventure, 8.0, intent: intent)
        expect(ctx["rest_clears_fatigue"]).to be true
        expect(ctx["hours_since_last_rest"]).to eq(0)
      end

      it "does not set rest_clears_fatigue for non-rest actions" do
        intent = { intention: "I walk to the market." }
        ctx = described_class.advance_clock!(adventure, 0.5, intent: intent)
        expect(ctx["rest_clears_fatigue"]).to be_nil
      end
    end
  end

  describe "TimeKeeper fatigue application" do
    let(:pipeline) { build_pipeline(adventure) }

    it "applies fatigued condition when threshold is crossed" do
      adventure.update!(time_context: {
        "current_hour" => 8,
        "adventure_day" => 1,
        "hours_since_last_rest" => 15,
        "hours_since_last_encounter_check" => 0
      })

      intent = { intention: "I walk through the forest.", destination: nil }

      ai_time_response = { "hours_elapsed" => 2.0 }.to_json
      allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
        instance.instance_variable_set(:@last_parse_status, "success")
        instance.instance_variable_set(:@last_model_used, "test")
        instance.instance_variable_set(:@last_usage, {})
        kwargs[:step_name] == "time_keeper" ? ai_time_response : AI_STEP_RESPONSES.fetch(kwargs[:step_name].to_s, '{}')
      end

      pipeline.send(:run_time_keeper, intent, {})

      expect(sheet.reload.conditions).to include("fatigued")
    end

    it "clears fatigue conditions on rest" do
      sheet.update_column(:conditions, ["fatigued"])
      adventure.update!(time_context: {
        "current_hour" => 22,
        "adventure_day" => 1,
        "hours_since_last_rest" => 20,
        "hours_since_last_encounter_check" => 0
      })

      intent = { intention: "I rest at the inn." }

      ai_time_response = { "hours_elapsed" => 8.0 }.to_json
      allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
        instance.instance_variable_set(:@last_parse_status, "success")
        instance.instance_variable_set(:@last_model_used, "test")
        instance.instance_variable_set(:@last_usage, {})
        kwargs[:step_name] == "time_keeper" ? ai_time_response : AI_STEP_RESPONSES.fetch(kwargs[:step_name].to_s, '{}')
      end

      pipeline.send(:run_time_keeper, intent, {})

      expect(sheet.reload.conditions).not_to include("fatigued")
    end
  end
end
