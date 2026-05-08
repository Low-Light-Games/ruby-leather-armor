# frozen_string_literal: true

module PlayerTurn
  module Timing
    module_function

    PAUSED_ACTIONS = %i[awaiting_rolls awaiting_initiative].freeze

    def run(log)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      segment_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      log.finish_pipeline_segment!(segment_ms)

      if result[:action].in?(PAUSED_ACTIONS)
        log.pause_registry_entry!
    else
        log.complete_registry_entry!
      end

      result
    end
  end
end
