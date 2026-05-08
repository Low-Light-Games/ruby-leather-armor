# frozen_string_literal: true

# Playwright env overrides ShipPlayLogJob's queue adapter to `:async` so
# the Axiom POST runs on a background thread instead of blocking the
# inline pipeline. Without this override, every PlayLog ship adds ~1800ms
# to the request-response cycle (around ten ships per turn → 15-20s of
# extra wall-clock per action), pushing realistic e2e turns past
# Playwright's per-step timeouts.
#
# Other ActiveJob queues remain on the global `:inline` adapter set in
# config/environments/playwright.rb — that's what guarantees pipeline
# events reach the browser via ActionCable before the HTTP response
# returns. We only decouple the *log shipping* job, mirroring the way
# Sidekiq handles it in dev/prod (Logging queue runs out-of-band).

return unless Rails.env.playwright?

Rails.application.config.after_initialize do
  ShipPlayLogJob.queue_adapter = :async
end
