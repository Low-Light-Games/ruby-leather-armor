# frozen_string_literal: true

module Api
  module Mcp
    class PlayLogsController < Api::BaseController
      include ListParams

      def index
        scope = PlayLog.recent_first
        scope = scope.for_adventure(params[:adventure_id])                  if params[:adventure_id].present?
        scope = scope.with_status(params[:status])                          if params[:status].present?
        scope = scope.with_event_type(params[:event_type])                  if params[:event_type].present?
        scope = scope.with_registry_entry_uuid(params[:registry_entry_uuid]) if params[:registry_entry_uuid].present?
        scope = scope.limit(clamped_limit(default: 50, max: 200))

        render json: scope.map { |l| PlayLogSerializer.call(l) }
      end

      def pipelines
        aggregates = PlayLog.pipeline_aggregates(limit: clamped_limit(default: 50, max: 200))
        render json: aggregates.map { |agg|
          PlayLogPipelineSerializer.call(
            uuid: agg[:uuid],
            log_count: agg[:log_count],
            started_at: agg[:started_at],
            ended_at: agg[:ended_at],
            had_error: agg[:had_error]
          )
        }
      end
    end
  end
end
