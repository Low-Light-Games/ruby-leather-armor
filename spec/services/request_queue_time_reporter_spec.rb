require "rails_helper"

RSpec.describe RequestQueueTimeReporter do
  def event_for(queue_time_ms:, shed: false)
    measurement = RequestQueueTime::Measurement.new(
      queue_time_ms: queue_time_ms,
      shed_after_ms: 10_000,
      shed: shed,
      request_id: "req-123",
      request_method: "GET",
      path: "/legal",
      measured_at: Time.current
    )
    ActiveSupport::Notifications::Event.new(RequestQueueTime::EVENT, nil, nil, "id", { measurement: measurement })
  end

  it "ships the slow tail to Axiom through a background job" do
    expect(ShipRequestQueueTimeJob).to receive(:perform_later)
      .with(hash_including(event_kind: "request_queue_time", queue_time_ms: described_class::REPORT_AFTER_MS))

    described_class.call(event_for(queue_time_ms: described_class::REPORT_AFTER_MS))
  end

  it "always ships shed requests" do
    expect(ShipRequestQueueTimeJob).to receive(:perform_later).with(hash_including(shed: true))

    described_class.call(event_for(queue_time_ms: 0, shed: true))
  end

  it "does not ship healthy requests" do
    expect(ShipRequestQueueTimeJob).not_to receive(:perform_later)

    described_class.call(event_for(queue_time_ms: 3))
  end

  it "reports instead of raising when the job cannot be enqueued" do
    allow(ShipRequestQueueTimeJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    expect(ApplicationErrorReporter).to receive(:notify)

    expect { described_class.call(event_for(queue_time_ms: 5_000)) }.not_to raise_error
  end
end
