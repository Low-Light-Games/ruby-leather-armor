require "rails_helper"

RSpec.describe RequestQueueTime do
  let(:downstream_body) { ["hello"] }
  let(:downstream) { ->(_env) { [200, Rack::Headers["server-timing" => "db;dur=12"], downstream_body] } }
  let(:middleware) do
    described_class.new(downstream, shed_after_ms: 10_000, retry_after_seconds: 7, exempt_paths: ["/up"])
  end

  def env_queued_for(seconds, path: "/legal", **extra)
    Rack::MockRequest.env_for(path, { "HTTP_X_REQUEST_START" => format("t=%.3f", Time.now.to_f - seconds) }.merge(extra))
  end

  around { |example| freeze_time { example.run } }

  it "reads the request start in seconds, milliseconds or microseconds" do
    epoch = Time.utc(2026, 10, 10, 12).to_f

    [format("t=%.3f", epoch), (epoch * 1e3).to_i.to_s, "t=#{(epoch * 1e6).to_i}"].each do |raw|
      expect(RequestQueueTime::RequestStartHeader.new(raw).started_at).to be_within(0.001).of(epoch)
    end
    expect(RequestQueueTime::RequestStartHeader.new("t=yesterday")).not_to be_present
  end

  it "passes requests without a request start through untouched" do
    _, headers, = middleware.call(Rack::MockRequest.env_for("/legal"))

    expect(headers["server-timing"]).to eq("db;dur=12")
  end

  it "appends the queue time to Server-Timing and leaves the body alone" do
    _, headers, body = middleware.call(env_queued_for(1.5))

    expect(headers["server-timing"]).to eq("db;dur=12, queue;dur=1500.0")
    expect(body).to be(downstream_body)
  end

  it "does not count a slow client upload as queue time" do
    _, headers, = middleware.call(env_queued_for(3, "puma.request_body_wait" => 2_000))

    expect(headers["server-timing"]).to end_with("queue;dur=1000.0")
  end

  it "sheds with a 503 once the wait passes the threshold, without calling the app" do
    expect(downstream).not_to receive(:call)

    status, headers, = middleware.call(env_queued_for(30))

    expect(status).to eq(503)
    expect(headers["retry-after"]).to eq("7")
  end

  it "never sheds exempt paths" do
    status, = middleware.call(env_queued_for(30, path: "/up"))

    expect(status).to eq(200)
  end
end
