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

  # Service specs that exercise the full pipeline spawn background threads for
  # parallel context updates (ContextUpdate module). After each example, wait
  # for any still-running threads and release their connections back to the pool
  # so the reaper never finds a connection owned by a dead thread.
  config.after(:each, type: :service) do
    Thread.list.reject { |t| t == Thread.current }.each { |t| t.join(2) }
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
