# When STUB_OPENAI=true is set (e.g. during Playwright E2E runs), intercept
# all outbound OpenAI API calls at the HTTP layer and return a canned response
# so tests never depend on a real API key or network access.
if ENV["STUB_OPENAI"].present?
  require "webmock"
  WebMock.enable!
  WebMock.allow_net_connect!(allow_localhost: true)

  stub_body = {
    id: "chatcmpl-stub",
    object: "chat.completion",
    created: Time.now.to_i,
    model: "gpt-4o-mini",
    choices: [{
      index: 0,
      message: {
        role: "assistant",
        content: '{"enriched_world":{},"enriched_premise":"A test adventure begins."}'
      },
      finish_reason: "stop"
    }],
    usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 }
  }.to_json

  WebMock.stub_request(:post, /api\.openai\.com/)
         .to_return(status: 200, body: stub_body, headers: { "Content-Type" => "application/json" })
end
