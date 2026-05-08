require "rails_helper"
require "webmock/rspec"

RSpec.describe Ai::Client do
  let(:config) { Struct.new(:model, :temperature).new("gpt-4o-mini", 1.0) }
  let(:client) { described_class.new(config) }
  let(:chat_url) { "https://api.openai.com/v1/chat/completions" }

  before do
    allow(client).to receive(:sleep)
  end

  it "retries a transient rate limit and succeeds on a later attempt" do
    stub_request(:post, chat_url)
      .to_return(
        { status: 429, headers: { "Retry-After" => "1" }, body: { error: { message: "slow down" } }.to_json },
        { status: 200, body: successful_chat_response("ok").to_json, headers: { "Content-Type" => "application/json" } }
      )

    expect(
      client.chat(system_prompt: "system", user_message: "hello", model: "gpt-4o-mini")
    ).to eq("ok")

    expect(client).to have_received(:sleep).with(1.0).once
    expect(a_request(:post, chat_url)).to have_been_made.twice
  end

  it "does not retry non-retryable client errors" do
    stub_request(:post, chat_url)
      .to_return(status: 400, body: { error: { message: "bad request" } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    expect do
      client.chat(system_prompt: "system", user_message: "hello", model: "gpt-4o-mini")
    end.to raise_error(Ai::Error, "AI request rejected: bad request")

    expect(client).not_to have_received(:sleep)
    expect(a_request(:post, chat_url)).to have_been_made.once
  end

  it "falls back to jittered backoff when Retry-After is malformed" do
    allow(client).to receive(:rand).and_return(0.4)

    stub_request(:post, chat_url)
      .to_return(
        { status: 429, headers: { "Retry-After" => "bogus" }, body: { error: { message: "slow down" } }.to_json },
        { status: 200, body: successful_chat_response("ok").to_json, headers: { "Content-Type" => "application/json" } }
      )

    client.chat(system_prompt: "system", user_message: "hello", model: "gpt-4o-mini")

    expect(client).to have_received(:sleep).with(0.2).once
  end

  def successful_chat_response(content)
    {
      id: "chatcmpl-1",
      object: "chat.completion",
      created: Time.now.to_i,
      model: "gpt-4o-mini",
      choices: [
        {
          index: 0,
          message: { role: "assistant", content: content },
          finish_reason: "stop"
        }
      ],
      usage: {
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
        completion_tokens_details: { reasoning_tokens: 0 }
      }
    }
  end
end
