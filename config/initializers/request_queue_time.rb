# frozen_string_literal: true

ActiveSupport::Notifications.subscribe(RequestQueueTime::EVENT) do |event|
  RequestQueueTimeReporter.call(event)
end
