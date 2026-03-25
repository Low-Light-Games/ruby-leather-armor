# frozen_string_literal: true

require "rails_helper"

RSpec.describe S3PayloadStore, type: :service do
  let(:bucket)     { "test-bucket" }
  let(:region)     { "us-east-1" }
  let(:access_key) { "AKIATEST" }
  let(:secret_key) { "secrettest" }
  let(:s3_client)  { instance_double(Aws::S3::Client) }

  before do
    ENV["AWS_S3_BUCKET"]           = bucket
    ENV["AWS_S3_REGION"]           = region
    ENV["AWS_S3_ACCESS_KEY_ID"]    = access_key
    ENV["AWS_S3_SECRET_ACCESS_KEY"] = secret_key

    allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
    allow(s3_client).to receive(:put_object)
  end

  after do
    %w[AWS_S3_BUCKET AWS_S3_REGION AWS_S3_ACCESS_KEY_ID AWS_S3_SECRET_ACCESS_KEY].each do |k|
      ENV.delete(k)
    end
  end

  describe ".upload" do
    let(:play_log_id) { 42 }
    let(:field_name)  { "raw_response" }
    let(:body)        { '{"result":"ok"}' }

    it "calls put_object on the S3 client with the correct bucket" do
      described_class.upload(play_log_id: play_log_id, field_name: field_name, body: body)
      expect(s3_client).to have_received(:put_object).with(
        hash_including(bucket: bucket)
      )
    end

    it "uses the key pattern play_logs/{id}/{field}.json" do
      described_class.upload(play_log_id: play_log_id, field_name: field_name, body: body)
      expect(s3_client).to have_received(:put_object).with(
        hash_including(key: "play_logs/#{play_log_id}/#{field_name}.json")
      )
    end

    it "passes the body to put_object" do
      described_class.upload(play_log_id: play_log_id, field_name: field_name, body: body)
      expect(s3_client).to have_received(:put_object).with(
        hash_including(body: body)
      )
    end

    it "returns the S3 HTTPS URL" do
      url = described_class.upload(play_log_id: play_log_id, field_name: field_name, body: body)
      expect(url).to eq("https://#{bucket}.s3.#{region}.amazonaws.com/play_logs/#{play_log_id}/#{field_name}.json")
    end

    it "initialises the S3 client with the non-standard env var credentials" do
      described_class.upload(play_log_id: play_log_id, field_name: field_name, body: body)
      expect(Aws::S3::Client).to have_received(:new).with(
        hash_including(
          region: region,
          credentials: an_instance_of(Aws::Credentials)
        )
      )
    end

    context "when the S3 client raises" do
      before { allow(s3_client).to receive(:put_object).and_raise(Aws::S3::Errors::ServiceError.new(nil, "access denied")) }

      it "propagates the error so the job can retry" do
        expect {
          described_class.upload(play_log_id: play_log_id, field_name: field_name, body: body)
        }.to raise_error(Aws::S3::Errors::ServiceError)
      end
    end
  end
end
