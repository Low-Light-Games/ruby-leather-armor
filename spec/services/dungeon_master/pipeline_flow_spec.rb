require "rails_helper"

# Full Pipeline#run_prompt happy-path integration spec.
# All AI calls are mocked. Exercises the complete step chain:
# intake → sequencer → player_interpreter → beacon → world_check →
# time_keeper → momentum → narrate
RSpec.describe "DungeonMaster::Pipeline — full prompt flow", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story)      { create(:story) }
  let(:user)       { create(:user) }
  let(:adventure)  { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline)   { build_pipeline(adventure) }

  describe "#run_prompt happy path (non-mechanical action)" do
    subject(:result) { pipeline.run_prompt("I open the door carefully.") }

    it "returns action: :narrated" do
      expect(result[:action]).to eq(:narrated)
    end

    it "includes a non-empty narrative string" do
      expect(result[:narrative]).to be_a(String).and be_present
    end

    it "includes adventure_complete flag" do
      expect(result).to have_key(:adventure_complete)
    end

    it "calls the intake step" do
      ai_spy = instance_spy(DungeonMaster::AiClient)
      allow(DungeonMaster::AiClient).to receive(:new).and_return(ai_spy)
      allow(ai_spy).to receive(:chat) do |**kwargs|
        ai_spy.instance_variable_set(:@last_parse_status, "success")
        ai_spy.instance_variable_set(:@last_model_used, "gpt-4o-mini-test")
        ai_spy.instance_variable_set(:@last_usage, {})
        AI_STEP_RESPONSES.fetch(kwargs[:step_name].to_s, '{"result":"ok"}')
      end
      allow(ai_spy).to receive(:parse_json) do |raw, **|
        JSON.parse(raw)
      end
      allow(ai_spy).to receive(:last_parse_status).and_return("success")
      allow(ai_spy).to receive(:last_model_used).and_return("gpt-4o-mini-test")
      allow(ai_spy).to receive(:last_usage).and_return({})
      allow(ai_spy).to receive(:last_failed_raw_response).and_return(nil)

      fresh_pipeline = build_pipeline(adventure)
      fresh_pipeline.run_prompt("I open the door carefully.")
      expect(ai_spy).to have_received(:chat).with(hash_including(step_name: "intake"))
    end

    it "produces a non-empty narrative (narrate step ran via Node fan-out)" do
      expect(result[:narrative]).to be_present
    end
  end

  describe "#run_prompt with action_queue disabled" do
    before do
      allow(DmConfig.instance).to receive(:get).and_call_original
      allow(DmConfig.instance).to receive(:get).with("action_queue").and_return(false)
    end

    it "still returns :narrated" do
      result = pipeline.run_prompt("I walk forward.")
      expect(result[:action]).to eq(:narrated)
    end
  end
end
