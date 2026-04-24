# frozen_string_literal: true

module DungeonMaster
  module Utilities
    module PipelineWarn
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
end
