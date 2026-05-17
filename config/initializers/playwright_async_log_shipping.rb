# frozen_string_literal: true

# Playwright env: log-shipping and fire-and-forget jobs use `:async` so
# Axiom POSTs and background loremaster calls run on separate threads
# instead of blocking the inline pipeline.
#
# The primary declarations live in each job class body (`self.queue_adapter
# = :async if Rails.env.playwright?`) so they survive code reloads
# (enable_reloading = true in playwright.rb would otherwise wipe any
# class-level assignment made here after the first reload).
#
# This after_initialize block is kept as belt-and-suspenders for boot-time
# correctness, matching the shape other environments use.
#
# Other ActiveJob queues remain on the global `:inline` adapter — that's
# what guarantees pipeline events reach the browser via ActionCable before
# the HTTP response returns.

return unless Rails.env.playwright?

Rails.application.config.after_initialize do
  ShipPlayLogJob.queue_adapter = :async
  ShipPipelineRegistryEntryEventJob.queue_adapter = :async
  GameMasterLoremasterJob.queue_adapter = :async
end
