require "active_support/core_ext/integer/time"

# Playwright E2E environment — inherits development behaviour with two changes:
#   1. Jobs run inline (no Sidekiq needed) so the pipeline executes synchronously
#      inside the request/response cycle.
#   2. ActionCable uses the async (in-process) adapter so WebSocket broadcasts
#      are delivered within the same Puma process without a Redis round-trip.
#      This makes pipeline_action_result events reliably visible to the browser
#      before the HTTP response returns.
# Suppress external telemetry so ShipPlayLogJob returns early on every call
# and does not add ~1800 ms × N to inline pipeline execution.
ENV.delete("AXIOM_API_KEY")
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

  # No credentials file for this environment — use an env var or a fixed
  # test-only value. Sessions don't need to survive server restarts in E2E runs.
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "playwright" + "0" * 118)
end
