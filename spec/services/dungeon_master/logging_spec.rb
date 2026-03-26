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

  # ── pipeline run lifecycle ─────────────────────────────────────────────────

  describe "#start_pipeline_run!" do
    it "enqueues ShipPipelineRunEventJob" do
      expect {
        logging.start_pipeline_run!("Hello")
      }.to have_enqueued_job(ShipPipelineRunEventJob)
    end

    it "passes the pipeline_run_id to the job" do
      logging.start_pipeline_run!("Hello")
      expect(ShipPipelineRunEventJob).to have_been_enqueued.with(logging.pipeline_run_id)
    end

    it "does not raise when the enqueue fails" do
      allow(ShipPipelineRunEventJob).to receive(:perform_later).and_raise(RuntimeError, "Redis down")
      expect { logging.start_pipeline_run!("Hello") }.not_to raise_error
    end
  end

  describe "#complete_pipeline_run!" do
    before { logging.start_pipeline_run!("Hello") }

    it "enqueues ShipPipelineRunEventJob" do
      expect { logging.complete_pipeline_run! }.to have_enqueued_job(ShipPipelineRunEventJob)
    end
  end

  describe "#error_pipeline_run!" do
    before { logging.start_pipeline_run!("Hello") }

    it "enqueues ShipPipelineRunEventJob" do
      expect { logging.error_pipeline_run! }.to have_enqueued_job(ShipPipelineRunEventJob)
    end
  end

  describe "#pause_pipeline_run!" do
    before { logging.start_pipeline_run!("Hello") }

    it "enqueues ShipPipelineRunEventJob" do
      expect { logging.pause_pipeline_run! }.to have_enqueued_job(ShipPipelineRunEventJob)
    end
  end
end
