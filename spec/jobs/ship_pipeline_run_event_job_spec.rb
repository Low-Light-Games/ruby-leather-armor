# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShipPipelineRunEventJob, type: :job do
  include ActiveJob::TestHelper

  let(:adventure) { create(:adventure) }
  let(:pipeline_run_id) { SecureRandom.uuid }
  let(:started_at) { 5.minutes.ago.utc }

  let!(:pipeline_run) do
    PipelineRun.create!(
      pipeline_run_id: pipeline_run_id,
      adventure: adventure,
      status: "completed",
      started_at: started_at,
      finished_at: Time.current.utc,
      active_duration_ms: 1200,
      step_count: 6,
      app_version: "1.0.0"
    )
  end

  before do
    ENV["AXIOM_API_KEY"] = "test-key"
    ENV["AXIOM_DATASET"] = "play_logs_test"
    allow(AxiomShipper).to receive(:ingest)
  end

  after do
    ENV.delete("AXIOM_API_KEY")
    ENV.delete("AXIOM_DATASET")
  end

  describe "#perform" do
    context "when AXIOM_API_KEY is present" do
      it "ships the pipeline run fields to Axiom" do
        described_class.perform_now(pipeline_run_id)
        expect(AxiomShipper).to have_received(:ingest).with(
          hash_including(
            pipeline_run_id:    pipeline_run_id,
            adventure_id:       adventure.id,
            status:             "completed",
            active_duration_ms: 1200,
            step_count:         6,
            app_version:        "1.0.0",
            event_kind:         "pipeline_run"
          )
        )
      end

      it "includes started_at as an ISO8601 string" do
        described_class.perform_now(pipeline_run_id)
        expect(AxiomShipper).to have_received(:ingest).with(
          hash_including(started_at: pipeline_run.started_at.utc.iso8601(3))
        )
      end

      it "includes finished_at as an ISO8601 string" do
        described_class.perform_now(pipeline_run_id)
        expect(AxiomShipper).to have_received(:ingest).with(
          hash_including(finished_at: pipeline_run.finished_at.utc.iso8601(3))
        )
      end

      it "does nothing when the PipelineRun record does not exist" do
        described_class.perform_now("nonexistent-run-id")
        expect(AxiomShipper).not_to have_received(:ingest)
      end
    end

    context "when AXIOM_API_KEY is blank" do
      before { ENV.delete("AXIOM_API_KEY") }

      it "does nothing" do
        described_class.perform_now(pipeline_run_id)
        expect(AxiomShipper).not_to have_received(:ingest)
      end
    end
  end
end
