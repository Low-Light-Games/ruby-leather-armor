require "rails_helper"

# Verifies that the pipeline propagates AI errors correctly so the
# calling service (DungeonMasterService) can catch and surface them safely.
RSpec.describe "DungeonMaster pipeline error handling", type: :service do
  include_context "with mocked ai"
  include_context "with evaluator stubs"

  let(:story)      { create(:story) }
  let(:user)       { create(:user) }
  let(:adventure)  { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) { create(:adventure_sheet, adventure: adventure) }
  let(:pipeline)   { build_pipeline(adventure) }

  # Helper: stub AiClient#chat to raise on any call
  def stub_ai_to_raise(error)
    allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat).and_raise(error)
  end

  describe "TokenBudgetExceededError" do
    let(:error) do
      DungeonMaster::TokenBudgetExceededError.new(step_name: "intake", budget: 400)
    end

    it "propagates from Pipeline#run_prompt" do
      stub_ai_to_raise(error)
      expect { pipeline.run_prompt("I open the door.") }
        .to raise_error(DungeonMaster::TokenBudgetExceededError)
    end

    it "carries step name and budget" do
      stub_ai_to_raise(error)
      begin
        pipeline.run_prompt("I open the door.")
      rescue DungeonMaster::TokenBudgetExceededError => caught
        expect(caught.step_name).to eq("intake")
        expect(caught.budget).to eq(400)
      end
    end
  end

  describe "AiError" do
    let(:error) { DungeonMaster::AiError.new("Model returned empty response") }

    it "propagates from Pipeline#run_prompt" do
      stub_ai_to_raise(error)
      expect { pipeline.run_prompt("I open the door.") }
        .to raise_error(DungeonMaster::AiError)
    end
  end

  describe "parse failure (intake returns no sanitized_input)" do
    before do
      allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
        instance.instance_variable_set(:@last_parse_status, "success")
        instance.instance_variable_set(:@last_model_used, "gpt-4o-mini-test")
        instance.instance_variable_set(:@last_usage, {})
        # Return JSON that is missing the required sanitized_input field
        '{"danger_score": 0, "reason": "ok", "is_dm_query": false}'
      end
    end

    it "raises AiError with a meaningful message" do
      expect { pipeline.run_prompt("I open the door.") }
        .to raise_error(DungeonMaster::AiError, /sanitized_input/)
    end
  end

  describe "narrate step returns no narrative" do
    before do
      allow_any_instance_of(DungeonMaster::Pipeline).to receive(:narrative_from_evaluator_result).and_raise(
        DungeonMaster::AiError.new("Narrate step returned no narrative — model produced: {}")
      )
    end

    it "raises AiError mentioning narrate" do
      expect { pipeline.run_prompt("I open the door.") }
        .to raise_error(DungeonMaster::AiError, /[Nn]arrate/)
    end
  end
end
