# frozen_string_literal: true

# Ships structured events to Axiom via the HTTP Ingest API.
# https://axiom.co/docs/send-data/ingest
#
# Automatically injects `environment: Rails.env` into every event so all three
# environments (development, staging, production) share one dataset but remain
# filterable.
#
# Errors are intentionally not rescued — the caller (a Sidekiq job) lets them
# propagate so Sidekiq retries and Sentry captures persistent failures.
class AxiomShipper
  INGEST_URL = "https://api.axiom.co/v1/datasets/%s/ingest"

  # events — an Array of Hashes or a single Hash
  def self.ingest(events)
    new.ingest(events)
  end

  def ingest(events)
    payload = Array.wrap(events).map { |e| e.merge(environment: Rails.env) }

    response = HTTParty.post(
      url,
      headers: {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type"  => "application/json"
      },
      body: payload.to_json
    )

    unless response.success?
      raise "AxiomShipper received #{response.code}: #{response.body.truncate(200)}"
    end

    response
  end

  private

  def url
    format(INGEST_URL, ENV.fetch("AXIOM_DATASET"))
  end

  def api_key
    ENV.fetch("AXIOM_API_KEY")
  end
end
