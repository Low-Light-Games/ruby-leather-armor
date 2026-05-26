# frozen_string_literal: true

module Api
  module Mcp
    class PlayLogsController < Api::BaseController
      MAX_LIMIT = 200
      DEFAULT_LIMIT = 50

      def index
        scope = PlayLog.recent_first
        scope = scope.for_adventure(params[:adventure_id]) if params[:adventure_id].present?
        scope = scope.with_status(params[:status]) if params[:status].present?
        scope = scope.with_event_type(params[:event_type]) if params[:event_type].present?
        scope = scope.with_registry_entry_uuid(params[:registry_entry_uuid]) if params[:registry_entry_uuid].present?
        scope = scope.limit(clamped_limit)

        render json: scope.map { |l| serialize(l) }
      end

      # Pipeline-grouped view: returns one row per registry_entry_uuid with aggregate stats.
      def pipelines
        rows = PlayLog
          .with_registry_entry_uuid_present
          .group(:registry_entry_uuid)
          .order(Arel.sql("MAX(created_at) DESC"))
          .limit(clamped_limit)
          .pluck(
            :registry_entry_uuid,
            Arel.sql("COUNT(*)"),
            Arel.sql("MIN(created_at)"),
            Arel.sql("MAX(created_at)"),
            Arel.sql("BOOL_OR(status NOT IN ('success', 'parse_fallback', 'pipeline_event'))")
          )

        render json: rows.map { |uuid, count, first_at, last_at, had_error|
          { registry_entry_uuid: uuid, log_count: count, started_at: first_at, ended_at: last_at, had_error: had_error }
        }
      end

      private

      def clamped_limit
        n = params[:limit].to_i
        return DEFAULT_LIMIT if n <= 0

        [n, MAX_LIMIT].min
      end

      def serialize(log)
        {
          id: log.id,
          adventure_id: log.adventure_id,
          player_message_id: log.player_message_id,
          registry_entry_uuid: log.registry_entry_uuid,
          event_type: log.event_type,
          status: log.status,
          dm_service: log.dm_service,
          prompt_summary: log.prompt_summary,
          created_at: log.created_at
        }
      end
    end
  end
end
