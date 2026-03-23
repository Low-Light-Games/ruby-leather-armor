return unless Rails.env.production? || Rails.env.staging?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env
  config.enabled_environments = %w[production staging]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.send_default_pii = true
end
