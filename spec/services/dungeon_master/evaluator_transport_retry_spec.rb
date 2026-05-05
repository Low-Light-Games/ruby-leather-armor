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

  it "retries read timeouts and surfaces the failure if every attempt times out" do
    allow(transport).to receive(:persist_node_logs)

    stub_request(:post, "#{transport_host}/fan_out")
      .to_raise(Net::ReadTimeout.new("execution expired"))

    expect do
      transport.send(:call_evaluator!, "#{transport_host}/fan_out", [{ foo: "bar" }], "intent", phase: "fan_out")
    end.to raise_error(DungeonMaster::AiError, /Evaluator fan_out failed/)

    expect(transport).not_to have_received(:persist_node_logs)
    expect(transport).not_to have_received(:persist_partial_logs)
    expect(a_request(:post, "#{transport_host}/fan_out"))
      .to have_been_made.times(transport.send(:evaluator_http_max_retries) + 1)
  end

  it "retries an HTTP 500 from the evaluator and surfaces the response if every attempt fails" do
    allow(transport).to receive(:persist_node_logs)

    stub_request(:post, "#{transport_host}/fan_out")
      .to_return(status: 500,
                 body: { error: "OpenAI call failed", partial_results: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    expect do
      transport.send(:call_evaluator!, "#{transport_host}/fan_out", [{ foo: "bar" }], "intent", phase: "fan_out")
    end.to raise_error(DungeonMaster::AiError, /Evaluator fan_out failed \(HTTP 500\)/)

    expect(a_request(:post, "#{transport_host}/fan_out"))
      .to have_been_made.times(transport.send(:evaluator_http_max_retries) + 1)
  end

  it "retries an HTTP 500 and persists logs when the next attempt succeeds" do
    allow(transport).to receive(:persist_node_logs)

    stub_request(:post, "#{transport_host}/fan_out")
      .to_return(status: 500,
                 body: { error: "OpenAI call failed", partial_results: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
      .then
      .to_return(status: 200,
                 body: [{ "meta" => { "step" => "narrate" } }].to_json,
                 headers: { "Content-Type" => "application/json" })

    result = transport.send(:call_evaluator!, "#{transport_host}/fan_out", [{ foo: "bar" }], "intent", phase: "fan_out")
    expect(result).to eq([{ "meta" => { "step" => "narrate" } }])
    expect(transport).to have_received(:persist_node_logs).once
    expect(a_request(:post, "#{transport_host}/fan_out")).to have_been_made.twice
  end

  describe "parse_error retry on individual prompts" do
    let(:log) do
      double("Logging").tap do |l|
        allow(l).to receive(:play_log!)
        allow(l).to receive(:truncate) { |s, **_| s.to_s }
      end
    end
    let(:transport_class_with_log) do
      Class.new do
        include DungeonMaster::Steps::EvaluatorTransport

        def initialize(base_url, log)
          @base_url = base_url
          @log = log
        end

        private

        def evaluator_base_url
          @base_url
        end
      end
    end
    let(:transport) { transport_class_with_log.new(transport_host, log) }

    let(:narrate_ok) do
      { "meta" => { "step" => "narrate" }, "parse_status" => "success",
        "raw_response" => "{}", "parsed_response" => {} }
    end
    let(:ctx_parse_error) do
      { "meta" => { "step" => "combat_context_update" }, "parse_status" => "parse_error",
        "raw_response" => "{ \"unchanged\":", "parsed_response" => nil }
    end
    let(:ctx_retry_ok) do
      { "meta" => { "step" => "combat_context_update" }, "parse_status" => "success",
        "raw_response" => "{\"unchanged\":true}", "parsed_response" => { "unchanged" => true } }
    end

    let(:original_payloads) do
      [
        { meta: { step: "narrate" }, system_prompt: "narrate sys", user_message: "u" },
        { meta: { step: "combat_context_update" }, system_prompt: "ctx sys", user_message: "u" },
      ]
    end

    before do
      allow(transport).to receive(:persist_node_logs)
    end

    it "re-issues only the failed prompt and replaces the result on success" do
      stub_request(:post, "#{transport_host}/fan_out")
        .to_return(
          { status: 200,
            body: [narrate_ok, ctx_parse_error].to_json,
            headers: { "Content-Type" => "application/json" } },
          { status: 200,
            body: [ctx_retry_ok].to_json,
            headers: { "Content-Type" => "application/json" } },
        )

      by_step = transport.send(:evaluator_fan_out!, original_payloads, "intent", phase: "narrative_phase")

      expect(by_step["narrate"]).to eq(narrate_ok)
      expect(by_step["combat_context_update"]).to eq(ctx_retry_ok)

      expect(log).to have_received(:play_log!).with(
        "parse_retry",
        a_string_including("combat_context_update"),
        hash_including(parsed_response: hash_including(step: "combat_context_update")),
      )

      expect(WebMock).to have_requested(:post, "#{transport_host}/fan_out")
        .with(body: original_payloads.to_json).once
      expect(WebMock).to have_requested(:post, "#{transport_host}/fan_out")
        .with(body: [original_payloads.last].to_json).once
    end

    it "leaves the original parse_error in place when the retry also returns parse_error" do
      stub_request(:post, "#{transport_host}/fan_out")
        .to_return(
          { status: 200,
            body: [narrate_ok, ctx_parse_error].to_json,
            headers: { "Content-Type" => "application/json" } },
          { status: 200,
            body: [ctx_parse_error].to_json,
            headers: { "Content-Type" => "application/json" } },
        )

      by_step = transport.send(:evaluator_fan_out!, original_payloads, "intent", phase: "narrative_phase")

      expect(by_step["combat_context_update"]).to eq(ctx_parse_error)
      expect(a_request(:post, "#{transport_host}/fan_out")).to have_been_made.twice
    end

    it "skips retry entirely when no result has parse_error" do
      stub_request(:post, "#{transport_host}/fan_out")
        .to_return(status: 200,
                   body: [narrate_ok, ctx_retry_ok].to_json,
                   headers: { "Content-Type" => "application/json" })

      transport.send(:evaluator_fan_out!, original_payloads, "intent", phase: "narrative_phase")

      expect(a_request(:post, "#{transport_host}/fan_out")).to have_been_made.once
      expect(log).not_to have_received(:play_log!)
    end
  end
end
