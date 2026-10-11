require_relative "boot"

require "rails/all"
require_relative "../lib/middleware/request_queue_time"

APP_VERSION = File.read(File.expand_path("../VERSION", __dir__)).strip

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets middleware tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # After RequestId so a shed request is traceable; before Rack::Attack so it costs no Redis call.
    config.middleware.insert_after ActionDispatch::RequestId, RequestQueueTime,
                                   shed_after_ms: ENV.fetch("REQUEST_QUEUE_SHED_AFTER_MS", "10000"),
                                   exempt_paths: ["/up"]
  end
end
