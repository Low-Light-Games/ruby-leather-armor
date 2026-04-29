require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  # Default ActiveJob queue adapter is :async — Concurrent::ScheduledTask
  # threads keep running after the spec returns and can hold connections
  # or hit unstubbed external services (OpenAI, Redis). Use the in-memory
  # :test adapter so perform_later just records the enqueue.
  config.before do
    ActiveJob::Base.queue_adapter = :test

    next unless defined?(Rack::Attack)

    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
