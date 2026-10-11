# frozen_string_literal: true

# The block defers the constant lookup to request time, keeping the reporter
# reloadable in development.
ActiveSupport::Notifications.subscribe(RequestQueueTime::EVENT) do |event|
  RequestQueueTimeReporter.call(event)
end
