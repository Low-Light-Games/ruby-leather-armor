# frozen_string_literal: true

module Api
  module Mcp
    # Serializes the aggregate row produced by PlayLog.pipeline_aggregates:
    # [registry_entry_uuid, count, first_at, last_at, had_error].
    class PlayLogPipelineSerializer
      def self.call(uuid:, log_count:, started_at:, ended_at:, had_error:)
        {
          registry_entry_uuid: uuid,
          log_count: log_count,
          started_at: started_at,
          ended_at: ended_at,
          had_error: had_error
        }
      end
    end
  end
end
