# Stub OpenAI HTTP calls when running E2E tests so no real API key is needed
# and adventure creation completes instantly.
#
# Activated by setting STUB_OPENAI=true in the environment (see playwright.config.js).
# Never loaded in production — webmock is not in the production bundle.
if ENV["STUB_OPENAI"] == "true"
  require "webmock"

  WebMock.enable!
  WebMock.allow_net_connect!(allow_localhost: true)

  stub_body = {
    id: "chatcmpl-stub",
    object: "chat.completion",
    created: 0,
    model: "gpt-4o-mini",
    choices: [{
      index: 0,
      message: {
        role: "assistant",
        content: '{"enriched_world":{},"enriched_premise":"A stubbed adventure begins.","new_npcs":[],"new_clues":[]}'
      },
      finish_reason: "stop"
    }],
    usage: {
      prompt_tokens: 1,
      completion_tokens: 1,
      total_tokens: 2
    }
  }.to_json

  WebMock.stub_request(:post, /api\.openai\.com/)
         .to_return(status: 200, body: stub_body, headers: { "Content-Type" => "application/json" })
end
