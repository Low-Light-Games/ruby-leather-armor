# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    # Per-action labels and play_log entries while processing a multi-action queue.
    # Wraps the pipeline's log object (AiLog / similar) — not Rails.logger.
    class ActionQueueLog
      def initialize(log)
        @log = log
      end

      def set_action_label(idx, total)
        @log.action_label = total > 1 ? "[action #{idx + 1}/#{total}]" : nil
      end

      def clear_action_label
        @log.action_label = nil
      end

      def log_pause(idx, total, remaining)
        return unless total > 1
        @log.play_log!("queue_paused", "Action queue paused at action #{idx + 1}/#{total} (awaiting rolls). Remaining: #{remaining.inspect}")
      end

      def log_interrupt(idx, total, remaining, reason: "encounter")
        return unless total > 1
        @log.play_log!("queue_interrupted", "Action queue interrupted at action #{idx + 1}/#{total} (#{reason}). Aborted: #{remaining.inspect}")
      end

      def log_completed(total)
        @log.play_log!("queue_completed", "Action queue completed: #{total}/#{total} actions resolved")
      end
    end
  end
end
