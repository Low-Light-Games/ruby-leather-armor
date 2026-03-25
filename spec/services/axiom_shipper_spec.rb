# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe AxiomShipper, type: :service do
  let(:api_key)  { "test-axiom-key" }
  let(:dataset)  { "play_logs_test" }
  let(:ingest_url) { "https://api.axiom.co/v1/datasets/#{dataset}/ingest" }

  before do
    ENV["AXIOM_API_KEY"]  = api_key
    ENV["AXIOM_DATASET"]  = dataset
  end

  after do
    ENV.delete("AXIOM_API_KEY")
    ENV.delete("AXIOM_DATASET")
  end

  describe ".ingest" do
    context "when the request succeeds" do
      before do
        stub_request(:post, ingest_url).to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "POSTs to the correct Axiom ingest URL" do
        described_class.ingest({ event_type: "narrate" })
        expect(WebMock).to have_requested(:post, ingest_url)
      end

      it "sends the Bearer token in the Authorization header" do
        described_class.ingest({ event_type: "narrate" })
        expect(WebMock).to have_requested(:post, ingest_url)
          .with(headers: { "Authorization" => "Bearer #{api_key}" })
      end

      it "sends a JSON Content-Type header" do
        described_class.ingest({ event_type: "narrate" })
        expect(WebMock).to have_requested(:post, ingest_url)
          .with(headers: { "Content-Type" => "application/json" })
      end

      it "injects environment into every event" do
        described_class.ingest({ event_type: "narrate" })
        expect(WebMock).to have_requested(:post, ingest_url)
          .with { |req| JSON.parse(req.body).first["environment"] == Rails.env }
      end

      it "accepts a single Hash and wraps it in an array" do
        described_class.ingest({ event_type: "narrate" })
        expect(WebMock).to have_requested(:post, ingest_url)
          .with { |req| JSON.parse(req.body).is_a?(Array) }
      end

      it "accepts an Array of events" do
        events = [{ event_type: "intake" }, { event_type: "narrate" }]
        described_class.ingest(events)
        expect(WebMock).to have_requested(:post, ingest_url)
          .with { |req| JSON.parse(req.body).size == 2 }
      end
    end

    context "when the server returns a non-2xx response" do
      before do
        stub_request(:post, ingest_url).to_return(status: 422, body: "Unprocessable")
      end

      it "raises an error so the Sidekiq job can retry" do
        expect { described_class.ingest({ event_type: "narrate" }) }.to raise_error(RuntimeError, /422/)
      end
    end
  end
end
