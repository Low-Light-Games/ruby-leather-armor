require "rails_helper"

RSpec.describe RequestQueueTime do
  let(:downstream_body) { ["hello"] }
  let(:downstream) { ->(_env) { [200, Rack::Headers["content-type" => "text/plain"], downstream_body] } }
  let(:middleware) do
    described_class.new(downstream, shed_after_ms: 10_000, retry_after_seconds: 7, exempt_paths: ["/up"])
  end

  def env_for(path = "/legal", request_start: nil, **extra)
    headers = request_start ? { "HTTP_X_REQUEST_START" => request_start } : {}
    Rack::MockRequest.env_for(path, headers.merge(extra))
  end

  def stamp_seconds_ago(seconds)
    format("t=%.3f", Time.now.to_f - seconds)
  end

  around do |example|
    freeze_time { example.run }
  end

  describe RequestQueueTime::RequestStartHeader do
    let(:epoch) { Time.utc(2026, 10, 10, 12, 0, 0).to_f }

    {
      "nginx $msec seconds with t= prefix" => ->(t) { format("t=%.3f", t) },
      "bare seconds" => ->(t) { format("%.3f", t) },
      "milliseconds" => ->(t) { (t * 1e3).to_i.to_s },
      "microseconds with t= prefix" => ->(t) { "t=#{(t * 1e6).to_i}" },
      "nanoseconds" => ->(t) { (t * 1e9).to_i.to_s }
    }.each do |format_name, render|
      it "normalises #{format_name} to epoch seconds" do
        header = described_class.new(render.call(epoch))

        expect(header.started_at).to be_within(0.001).of(epoch)
      end
    end

    it "treats an absent or malformed header as not present" do
      expect(described_class.new(nil)).not_to be_present
      expect(described_class.new("")).not_to be_present
      expect(described_class.new("t=yesterday")).not_to be_present
      expect(described_class.new("t=0")).not_to be_present
    end
  end

  it "passes requests without an X-Request-Start header through untouched" do
    expect(ActiveSupport::Notifications).not_to receive(:instrument)

    status, headers, = middleware.call(env_for)

    expect(status).to eq(200)
    expect(headers).not_to have_key("server-timing")
  end

  it "reports the queue time as a Server-Timing metric without replacing the body" do
    status, headers, body = middleware.call(env_for(request_start: stamp_seconds_ago(1.5)))

    expect(status).to eq(200)
    expect(headers["server-timing"]).to eq("queue;dur=1500.0")
    expect(body).to be(downstream_body)
  end

  it "appends to a Server-Timing header the app already set" do
    downstream = ->(_env) { [200, Rack::Headers["server-timing" => "db;dur=12"], []] }
    middleware = described_class.new(downstream, shed_after_ms: 10_000)

    _, headers, = middleware.call(env_for(request_start: stamp_seconds_ago(0.2)))

    expect(headers["server-timing"]).to eq("db;dur=12, queue;dur=200.0")
  end

  it "does not count Puma's wait for a slow request body as queue time" do
    env = env_for(request_start: stamp_seconds_ago(3), "puma.request_body_wait" => 2_000)

    _, headers, = middleware.call(env)

    expect(headers["server-timing"]).to eq("queue;dur=1000.0")
  end

  it "floors negative queue time from proxy clock skew at zero" do
    _, headers, = middleware.call(env_for(request_start: stamp_seconds_ago(-2)))

    expect(headers["server-timing"]).to eq("queue;dur=0.0")
  end

  it "instruments a measurement carrying the request id" do
    events = []
    callback = ->(event) { events << event.payload.fetch(:measurement) }
    env = env_for(request_start: stamp_seconds_ago(0.25), "action_dispatch.request_id" => "req-123")

    ActiveSupport::Notifications.subscribed(callback, described_class::EVENT) { middleware.call(env) }

    expect(events.size).to eq(1)
    expect(events.first).to have_attributes(queue_time_ms: 250.0, request_id: "req-123", path: "/legal", shed?: false)
  end

  describe "load shedding" do
    it "answers with a JSON 503 and never calls the app once the wait exceeds the threshold" do
      expect(downstream).not_to receive(:call)

      status, headers, body = middleware.call(env_for(request_start: stamp_seconds_ago(30)))

      expect(status).to eq(503)
      expect(headers["retry-after"]).to eq("7")
      expect(headers["content-type"]).to eq("application/json")
      expect(headers["server-timing"]).to eq("queue;dur=30000.0")
      expect(JSON.parse(body.join)).to include("error_code" => "request_queue_timeout")
    end

    it "never sheds exempt paths such as the health check" do
      status, = middleware.call(env_for("/up", request_start: stamp_seconds_ago(30)))

      expect(status).to eq(200)
    end

    it "is disabled when the threshold is zero" do
      middleware = described_class.new(downstream, shed_after_ms: 0)

      status, = middleware.call(env_for(request_start: stamp_seconds_ago(300)))

      expect(status).to eq(200)
    end
  end
end
