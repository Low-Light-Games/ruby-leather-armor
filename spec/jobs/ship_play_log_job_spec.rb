# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShipPlayLogJob, type: :job do
  include ActiveJob::TestHelper

  let(:adventure) { create(:adventure) }
  let(:pipeline_run_id) { SecureRandom.uuid }

  let!(:play_log) do
    PlayLog.create!(
      adventure: adventure,
      event_type: "narrate",
      prompt_summary: "Player opened a door",
      raw_response: '{"narrative":"The door swings open."}',
      request_body: '{"system_prompt":"You are a DM","user_message":"I open the door"}',
      parsed_response: '{"narrative":"The door swings open."}',
      status: "success",
      dm_service: "standard",
      model_used: "gpt-4o-mini",
      duration_ms: 320,
      pipeline_run_id: pipeline_run_id,
      player_message_content: "I open the door",
      app_version: "1.0.0"
    )
  end

  before do
    ENV["AXIOM_API_KEY"]           = "test-key"
    ENV["AXIOM_DATASET"]           = "play_logs_test"
    ENV["AWS_S3_ACCESS_KEY_ID"]    = "AKIATEST"
    ENV["AWS_S3_SECRET_ACCESS_KEY"] = "secrettest"
    ENV["AWS_S3_BUCKET"]           = "test-bucket"
    ENV["AWS_S3_REGION"]           = "us-east-1"

    allow(S3PayloadStore).to receive(:upload).and_return("https://s3.example.com/key")
    allow(AxiomShipper).to receive(:ingest)
  end

  after do
    %w[AXIOM_API_KEY AXIOM_DATASET AWS_S3_ACCESS_KEY_ID AWS_S3_SECRET_ACCESS_KEY AWS_S3_BUCKET AWS_S3_REGION].each do |k|
      ENV.delete(k)
    end
  end

  describe "#perform" do
    context "when AXIOM_API_KEY is present" do
      it "uploads request_body to S3" do
        described_class.perform_now(play_log.id)
        expect(S3PayloadStore).to have_received(:upload).with(
          hash_including(play_log_id: play_log.id, field_name: "request_body")
        )
      end

      it "uploads raw_response to S3" do
        described_class.perform_now(play_log.id)
        expect(S3PayloadStore).to have_received(:upload).with(
          hash_including(play_log_id: play_log.id, field_name: "raw_response")
        )
      end

      it "uploads parsed_response to S3" do
        described_class.perform_now(play_log.id)
        expect(S3PayloadStore).to have_received(:upload).with(
          hash_including(play_log_id: play_log.id, field_name: "parsed_response")
        )
      end

      it "does not upload nil blob fields" do
        play_log.update_columns(request_body: nil)
        described_class.perform_now(play_log.id)
        expect(S3PayloadStore).not_to have_received(:upload).with(
          hash_including(field_name: "request_body")
        )
      end

      it "ships a lean event to Axiom with core fields" do
        described_class.perform_now(play_log.id)
        expect(AxiomShipper).to have_received(:ingest).with(
          hash_including(
            play_log_id:            play_log.id,
            event_type:             "narrate",
            status:                 "success",
            model_used:             "gpt-4o-mini",
            duration_ms:            320,
            prompt_summary:         "Player opened a door",
            pipeline_run_id:        pipeline_run_id,
            adventure_id:           adventure.id,
            app_version:            "1.0.0"
          )
        )
      end

      it "sets _time to the play_log created_at, not job execution time" do
        described_class.perform_now(play_log.id)
        expect(AxiomShipper).to have_received(:ingest).with(
          hash_including(_time: play_log.created_at.utc.iso8601(3))
        )
      end

      it "includes S3 URLs in the Axiom payload" do
        described_class.perform_now(play_log.id)
        expect(AxiomShipper).to have_received(:ingest).with(
          hash_including(
            s3_request_body_url:   "https://s3.example.com/key",
            s3_raw_response_url:   "https://s3.example.com/key",
            s3_parsed_response_url: "https://s3.example.com/key"
          )
        )
      end

      context "when an AiUsageRecord is attached" do
        let!(:usage_record) do
          AiUsageRecord.create!(
            ai_log_id:              play_log.id,
            adventure_id:           adventure.id,
            model_id:               "gpt-4o-mini",
            event_type:             "narrate",
            input_tokens:           100,
            output_tokens:          50,
            reasoning_tokens:       0,
            total_tokens:           150,
            input_cost_microdollars:  150,
            output_cost_microdollars: 300,
            total_cost_microdollars:  450
          ).tap { |r| play_log.update_column(:ai_usage_record_id, r.id) }
        end

        it "includes flattened token counts in the Axiom event" do
          described_class.perform_now(play_log.id)
          expect(AxiomShipper).to have_received(:ingest).with(
            hash_including(
              input_tokens:   100,
              output_tokens:  50,
              total_tokens:   150
            )
          )
        end

        it "includes cost fields in the Axiom event" do
          described_class.perform_now(play_log.id)
          expect(AxiomShipper).to have_received(:ingest).with(
            hash_including(total_cost_microdollars: 450)
          )
        end
      end

      context "when no AiUsageRecord is attached" do
        it "does not include token or cost fields" do
          described_class.perform_now(play_log.id)
          expect(AxiomShipper).to have_received(:ingest).with(
            satisfy { |event| !event.key?(:input_tokens) && !event.key?(:total_cost_microdollars) }
          )
        end
      end

      context "when AWS_S3_ACCESS_KEY_ID is blank" do
        before { ENV.delete("AWS_S3_ACCESS_KEY_ID") }

        it "skips S3 uploads entirely" do
          described_class.perform_now(play_log.id)
          expect(S3PayloadStore).not_to have_received(:upload)
        end

        it "still ships to Axiom without S3 URLs" do
          described_class.perform_now(play_log.id)
          expect(AxiomShipper).to have_received(:ingest)
        end
      end
    end

    context "when AXIOM_API_KEY is blank" do
      before { ENV.delete("AXIOM_API_KEY") }

      it "does nothing" do
        described_class.perform_now(play_log.id)
        expect(S3PayloadStore).not_to have_received(:upload)
        expect(AxiomShipper).not_to have_received(:ingest)
      end
    end
  end
end
