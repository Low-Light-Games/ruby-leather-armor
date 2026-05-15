# frozen_string_literal: true

# Playwright env overrides log-shipping jobs to `:async` so Axiom POSTs
# run on background threads instead of blocking the inline pipeline.
# Without this override, per-turn shipping can add enough wall-clock to
# push realistic e2e actions past Playwright's per-step timeouts.
#
# Other ActiveJob queues remain on the global `:inline` adapter set in
# config/environments/playwright.rb — that's what guarantees pipeline
# events reach the browser via ActionCable before the HTTP response
# returns. We only decouple the *log shipping* job, mirroring the way
# Sidekiq handles it in dev/prod (Logging queue runs out-of-band).

return unless Rails.env.playwright?

Rails.application.config.after_initialize do
  ShipPlayLogJob.queue_adapter = :async
  ShipPipelineRegistryEntryEventJob.queue_adapter = :async
end
