require "rails_helper"

RSpec.describe "Request queue time", type: :request do
  def stamp_seconds_ago(seconds)
    format("t=%.3f", Time.now.to_f - seconds)
  end

  it "sits directly after RequestId and ahead of Rack::Attack" do
    stack = Rails.application.middleware.middlewares

    expect(stack.index(RequestQueueTime)).to eq(stack.index(ActionDispatch::RequestId) + 1)
    expect(stack.index(RequestQueueTime)).to be < stack.index(Rack::Attack)
  end

  it "exposes the queue time of a served request through Server-Timing" do
    get "/legal", headers: { "X-Request-Start" => stamp_seconds_ago(0.05) }

    expect(response).to have_http_status(:ok)
    expect(response.headers["server-timing"]).to match(/queue;dur=\d+(\.\d+)?/)
  end

  it "sheds a request that already outwaited the threshold, still tagged with its request id" do
    get "/legal", headers: { "X-Request-Start" => stamp_seconds_ago(60) }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["retry-after"]).to be_present
    expect(response.headers["x-request-id"]).to be_present
    expect(response.parsed_body["error_code"]).to eq("request_queue_timeout")
  end

  it "keeps answering the health check however long it queued" do
    get "/up", headers: { "X-Request-Start" => stamp_seconds_ago(60) }

    expect(response).to have_http_status(:ok)
  end
end
