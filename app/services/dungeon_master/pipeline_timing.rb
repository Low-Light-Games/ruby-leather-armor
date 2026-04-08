# frozen_string_literal: true

module DungeonMaster
  # Wraps a pipeline yield: wall-clock segment for PipelineRun, then pause vs complete
  # from the halt action (rolls / initiative vs terminal outcomes).
  module PipelineTiming
    module_function

    PAUSED_ACTIONS = %i[awaiting_rolls awaiting_initiative].freeze

    def run(log)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      segment_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      log.finish_pipeline_segment!(segment_ms)

      if result[:action].in?(PAUSED_ACTIONS)
        log.pause_pipeline_run!
      else
        log.complete_pipeline_run!
      end

      result
    end
  end
end
