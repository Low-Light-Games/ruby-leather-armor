# frozen_string_literal: true

module PlayerTurn
  module LogWarn
    module_function

    def emit(log, message)
      if log.respond_to?(:log!)
        log.log!(:warn, message)
      else
        Rails.logger.warn(message)
      end
    end
  end
end
