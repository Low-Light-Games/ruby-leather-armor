require "rails_helper"
require "webmock/rspec"

RSpec.describe DungeonMaster::Steps::EvaluatorTransport do
  let(:transport_host) { "http://evaluator.test:3001" }
  let(:transport_class) do
    Class.new do
      include DungeonMaster::Steps::EvaluatorTransport

      def initialize(base_url)
        @base_url = base_url
      end

      private

      def evaluator_base_url
        @base_url
      end
    end
  end
  let(:transport) { transport_class.new(transport_host) }

  before do
    allow(transport).to receive(:sleep)
    allow(transport).to receive(:rand).and_return(0.4)
    allow(transport).to receive(:persist_partial_logs)
  end

  it "retries a connect/open-timeout style failure and persists success logs once" do
    allow(transport).to receive(:persist_node_logs)

    stub_request(:post, "#{transport_host}/fan_out")
      .to_raise(Errno::ECONNREFUSED)
      .then
      .to_return(status: 200, body: [{ "meta" => { "step" => "narrate" } }].to_json,
                 headers: { "Content-Type" => "application/json" })

    result = transport.send(:call_evaluator!, "#{transport_host}/fan_out", [{ foo: "bar" }], "intent", phase: "fan_out")

    expect(result).to eq([{ "meta" => { "step" => "narrate" } }])
    expect(transport).to have_received(:persist_node_logs).once.with([{ "meta" => { "step" => "narrate" } }], "intent")
    expect(transport).not_to have_received(:persist_partial_logs)
    expect(transport).to have_received(:sleep).with(0.1).once
    expect(a_request(:post, "#{transport_host}/fan_out")).to have_been_made.twice
  end

  it "does not retry read timeouts" do
    allow(transport).to receive(:persist_node_logs)

    stub_request(:post, "#{transport_host}/fan_out")
      .to_raise(Net::ReadTimeout.new("execution expired"))

    expect do
      transport.send(:call_evaluator!, "#{transport_host}/fan_out", [{ foo: "bar" }], "intent", phase: "fan_out")
    end.to raise_error(DungeonMaster::AiError, /Evaluator unreachable during fan_out/)

    expect(transport).not_to have_received(:persist_node_logs)
    expect(transport).not_to have_received(:persist_partial_logs)
    expect(transport).not_to have_received(:sleep)
    expect(a_request(:post, "#{transport_host}/fan_out")).to have_been_made.once
  end
end
