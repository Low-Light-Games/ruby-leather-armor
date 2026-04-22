# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Logging, type: :service do
  include ActiveJob::TestHelper

  let(:user)      { create(:user) }
  let(:adventure) { create(:adventure, user: user) }
  let(:logging)   { described_class.new(adventure: adventure, user: user) }

  let(:fake_error) { StandardError.new("something went wrong") }

  before { allow(Rails.error).to receive(:report) }

  # ── play_log! ──────────────────────────────────────────────────────────────

  describe "#play_log!" do
    it "enqueues ShipPlayLogJob after creating the PlayLog" do
      expect {
        logging.play_log!("queue_paused", "Queue is full")
      }.to have_enqueued_job(ShipPlayLogJob)
    end

    it "passes the new PlayLog's id to the job" do
      logging.play_log!("queue_paused", "Queue is full")
      log_id = PlayLog.last.id
      expect(ShipPlayLogJob).to have_been_enqueued.with(log_id)
    end

    it "does not enqueue a job when PlayLog.create! fails" do
      allow(PlayLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect {
        logging.play_log!("queue_paused", "Queue is full")
      }.not_to have_enqueued_job(ShipPlayLogJob)
    end

    it "does not raise when the enqueue itself fails" do
      allow(ShipPlayLogJob).to receive(:perform_later).and_raise(RuntimeError, "Redis down")
      expect { logging.play_log!("queue_paused", "Queue is full") }.not_to raise_error
    end

    it "reports an enqueue failure to Sentry as a handled error" do
      allow(ShipPlayLogJob).to receive(:perform_later).and_raise(RuntimeError, "Redis down")
      logging.play_log!("queue_paused", "Queue is full")
      expect(Rails.error).to have_received(:report).with(an_instance_of(RuntimeError), handled: true, context: anything)
    end
  end

  # ── ai_log! ────────────────────────────────────────────────────────────────

  describe "#ai_log!" do
    let(:usage) { { input_tokens: 10, output_tokens: 20, reasoning_tokens: 0, total_tokens: 30 } }

    it "enqueues ShipPlayLogJob after the call completes" do
      expect {
        logging.ai_log!("narrate", "summary", "raw", { narrative: "ok" }, parse_status: "success",
                        model_used: "gpt-4o-mini", usage: usage)
      }.to have_enqueued_job(ShipPlayLogJob)
    end

    it "enqueues AFTER attach_usage_record! so AiUsageRecord exists when the job runs" do
      captured_log_id = nil
      allow(ShipPlayLogJob).to receive(:perform_later) { |id| captured_log_id = id }

      logging.ai_log!("narrate", "summary", "raw", { narrative: "ok" }, parse_status: "success",
                      model_used: "gpt-4o-mini", usage: usage)

      expect(PlayLog.find(captured_log_id).ai_usage_record).not_to be_nil
    end

    it "does not enqueue a job when PlayLog.create! fails" do
      allow(PlayLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect {
        logging.ai_log!("narrate", "summary", "raw", { narrative: "ok" }, parse_status: "success")
      }.not_to have_enqueued_job(ShipPlayLogJob)
    end

    it "does not raise when the enqueue itself fails" do
      allow(ShipPlayLogJob).to receive(:perform_later).and_raise(RuntimeError, "Redis down")
      expect {
        logging.ai_log!("narrate", "summary", "raw", { narrative: "ok" }, parse_status: "success")
      }.not_to raise_error
    end
  end

  # ── ai_log_error! ──────────────────────────────────────────────────────────

  describe "#ai_log_error!" do
    it "enqueues ShipPlayLogJob" do
      expect {
        logging.ai_log_error!("narrate", "summary", fake_error)
      }.to have_enqueued_job(ShipPlayLogJob)
    end

    it "does not raise when the enqueue itself fails" do
      allow(ShipPlayLogJob).to receive(:perform_later).and_raise(RuntimeError, "Redis down")
      expect { logging.ai_log_error!("narrate", "summary", fake_error) }.not_to raise_error
    end
  end

  # ── timed_chat_call ────────────────────────────────────────────────────────

  describe "#timed_chat_call" do
    let(:ai) { instance_double(DungeonMaster::AiClient) }

    before do
      allow(ai).to receive(:last_parse_status).and_return("success")
      allow(ai).to receive(:last_model_used).and_return("gpt-4.1-mini")
      allow(ai).to receive(:last_usage).and_return({ "total_tokens" => 42 })
      allow(ai).to receive(:last_failed_raw_response).and_return(nil)
    end

    it "writes a success PlayLog with duration, model, and parsed payload on happy path" do
      parsed = { "narrative" => "ok" }

      result = logging.timed_chat_call("narrate", "summary", ai: ai) do
        ["raw response body", parsed]
      end

      expect(result).to eq(parsed)

      row = PlayLog.where(event_type: "narrate").last
      expect(row).to be_present
      expect(row.status).to eq("success")
      expect(row.raw_response).to eq("raw response body")
      expect(JSON.parse(row.parsed_response)).to eq(parsed)
      expect(row.model_used).to eq("gpt-4.1-mini")
      expect(row.duration_ms).to be_a(Integer).and(be >= 0)
    end

    it "writes an api_error PlayLog and re-raises on AiError" do
      allow(ai).to receive(:last_failed_raw_response).and_return("partial raw body")

      expect {
        logging.timed_chat_call("narrate", "summary", ai: ai) do
          raise DungeonMaster::AiError, "upstream blew up"
        end
      }.to raise_error(DungeonMaster::AiError, "upstream blew up")

      row = PlayLog.where(event_type: "narrate").last
      expect(row).to be_present
      expect(row.status).to eq("api_error")
      expect(row.error_message).to eq("upstream blew up")
      expect(row.raw_response).to eq("partial raw body")
      expect(row.duration_ms).to be_a(Integer).and(be >= 0)
    end

    it "writes a token_budget_exceeded PlayLog and re-raises on TokenBudgetExceededError" do
      expect {
        logging.timed_chat_call("narrate", "summary", ai: ai) do
          raise DungeonMaster::TokenBudgetExceededError.new(step_name: "narrate", budget: 500)
        end
      }.to raise_error(DungeonMaster::TokenBudgetExceededError)

      row = PlayLog.where(event_type: "narrate").last
      expect(row.status).to eq("token_budget_exceeded")
    end

    it "threads request_body through to the success log when provided" do
      logging.timed_chat_call("narrate", "summary", ai: ai, request_body: { user_message: "hi" }) do
        ["raw", { "ok" => true }]
      end

      row = PlayLog.where(event_type: "narrate").last
      expect(JSON.parse(row.request_body)).to eq({ "user_message" => "hi" })
    end

    it "does not swallow non-AI exceptions from the block" do
      expect {
        logging.timed_chat_call("narrate", "summary", ai: ai) do
          raise ArgumentError, "programmer error"
        end
      }.to raise_error(ArgumentError)

      expect(PlayLog.where(event_type: "narrate")).to be_empty
    end
  end

  # ── pipeline registry entry lifecycle ───────────────────────────────────────

  describe "#start_registry_entry!" do
    it "enqueues ShipPipelineRegistryEntryEventJob" do
      expect {
        logging.start_registry_entry!("Hello")
      }.to have_enqueued_job(ShipPipelineRegistryEntryEventJob)
    end

    it "passes the registry_entry_uuid to the job" do
      logging.start_registry_entry!("Hello")
      expect(ShipPipelineRegistryEntryEventJob).to have_been_enqueued.with(logging.registry_entry_uuid)
    end

    it "does not raise when the enqueue fails" do
      allow(ShipPipelineRegistryEntryEventJob).to receive(:perform_later).and_raise(RuntimeError, "Redis down")
      expect { logging.start_registry_entry!("Hello") }.not_to raise_error
    end
  end

  describe "#complete_registry_entry!" do
    before { logging.start_registry_entry!("Hello") }

    it "enqueues ShipPipelineRegistryEntryEventJob" do
      expect { logging.complete_registry_entry! }.to have_enqueued_job(ShipPipelineRegistryEntryEventJob)
    end
  end

  describe "#error_registry_entry!" do
    before { logging.start_registry_entry!("Hello") }

    it "enqueues ShipPipelineRegistryEntryEventJob" do
      expect { logging.error_registry_entry! }.to have_enqueued_job(ShipPipelineRegistryEntryEventJob)
    end
  end

  describe "#capture_pipeline_exception!" do
    before do
      logging.start_registry_entry!("Hello")
      allow(Rails.logger).to receive(:error)
    end

    it "reports to Rails.error and logs the backtrace to Rails logger" do
      error = RuntimeError.new("boom")
      error.set_backtrace(["line1", "line2"])

      logging.capture_pipeline_exception!(error)

      expect(Rails.error).to have_received(:report).with(error, handled: true, context: anything)
      expect(Rails.logger).to have_received(:error).with(/RuntimeError: boom.*line1/m)
    end
  end

  describe "#pause_registry_entry!" do
    before { logging.start_registry_entry!("Hello") }

    it "enqueues ShipPipelineRegistryEntryEventJob" do
      expect { logging.pause_registry_entry! }.to have_enqueued_job(ShipPipelineRegistryEntryEventJob)
    end
  end

  describe "#log_abandoned_pipeline_if_needed!" do
    let!(:roll_request) do
      create(:adventure_message,
        adventure: adventure,
        role: "dm",
        message_type: "roll_request",
        metadata: { "intent" => { "intention" => "I sneak up to the goblins" } })
    end

    it "writes a pipeline_abandoned play log when a fresh prompt supersedes a pending roll request" do
      create(:adventure_message,
        adventure: adventure,
        role: "player",
        message_type: "narrative",
        content: "Actually, I'll do something else.")

      expect {
        logging.log_abandoned_pipeline_if_needed!
      }.to change { PlayLog.where(event_type: "pipeline_abandoned").count }.by(1)
    end

    it "does not log abandonment when the latest player response is a roll result" do
      create(:adventure_message,
        adventure: adventure,
        role: "player",
        message_type: "roll_result",
        content: "Rolled 18 for: Stealth check")

      expect {
        logging.log_abandoned_pipeline_if_needed!
      }.not_to change { PlayLog.where(event_type: "pipeline_abandoned").count }
    end
  end
end
