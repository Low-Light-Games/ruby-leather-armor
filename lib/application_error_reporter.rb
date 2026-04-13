# frozen_string_literal: true

# Central place for reporting handled errors so production never loses visibility:
# Sentry (when loaded) plus Rails.error (ErrorReporter), without raising.
module ApplicationErrorReporter
  module_function

  def notify(exception, context: {})
    return if exception.nil?

    ctx = context.stringify_keys
    Sentry.capture_exception(exception, extra: ctx) if defined?(Sentry)
    Rails.error.report(exception, handled: true, context: ctx) if Rails.error.respond_to?(:report)
  rescue StandardError => e
    Rails.logger.error("[ApplicationErrorReporter] #{e.class}: #{e.message}")
  end
end
