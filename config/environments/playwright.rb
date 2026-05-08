require "active_support/core_ext/integer/time"

# Playwright E2E environment — inherits development behaviour with two changes:
#   1. Jobs run inline (no Sidekiq needed) so the pipeline executes synchronously
#      inside the request/response cycle.
#   2. ActionCable uses the async (in-process) adapter so WebSocket broadcasts
#      are delivered within the same Puma process without a Redis round-trip.
#      This makes pipeline_action_result events reliably visible to the browser
#      before the HTTP response returns.
#
# Telemetry: Axiom shipping is enabled here so e2e pipeline runs are
# observable (events tagged `environment: playwright`). ShipPlayLogJob is
# routed through the `:async` ActiveJob adapter (set in
# config/initializers/playwright_async_log_shipping.rb) so the Axiom POST
# runs on a background thread instead of blocking the inline pipeline —
# matching the out-of-band shipping shape that Sidekiq provides in dev/prod.
#
# S3 blob storage is intentionally suppressed: the playwright env never
# uploads `request_body` / `raw_response` / `parsed_response` blobs to S3,
# regardless of whether AWS_S3_ACCESS_KEY_ID happens to be present in the
# environment. The PlayLog row in Postgres still has the blobs locally if
# they're needed for debugging. Avoids extra latency per ship + keeps the
# S3 bucket free of e2e noise.
ENV.delete("AWS_S3_ACCESS_KEY_ID")

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  config.active_storage.service = :local

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = false

  config.assets.quiet = true

  # ── Key differences from development ──────────────────────────────────────
  # Jobs execute synchronously in the request thread — no worker process needed.
  config.active_job.queue_adapter = :inline

  # Allow ActionCable from any origin (same as development).
  config.action_cable.disable_request_forgery_protection = true

  config.hosts << "localhost"
  # When the browser runs inside a sibling Docker container (compose.e2e.yml's
  # `playwright` service), it reaches the Rails service over the internal
  # network at http://app:3000 — allow that hostname through host authorization.
  config.hosts << "app"

  # No credentials file for this environment — use an env var or a fixed
  # test-only value. Sessions don't need to survive server restarts in E2E runs.
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "playwright" + "0" * 118)
end
