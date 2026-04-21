# frozen_string_literal: true

module Admin
  class PlayLogPipelineQuery
    AGGREGATE_SELECT_SQL = <<~SQL.squish
      registry_entry_uuid,
      MIN(created_at) AS first_at,
      MAX(created_at) AS last_at,
      COUNT(*) AS step_count,
      MIN(adventure_id) AS adventure_id
    SQL

    def initialize(page:, per_page:)
      @page = [page.to_i, 1].max
      @per_page = per_page
    end

    def paged_aggregates
      PlayLog.with_registry_entry_uuid_present
             .select(AGGREGATE_SELECT_SQL)
             .group(:registry_entry_uuid)
             .order("first_at DESC")
             .offset(offset)
             .limit(@per_page)
    end

    def total_count
      PlayLog.with_registry_entry_uuid_present.distinct.count(:registry_entry_uuid)
    end

    private

    def offset
      (@page - 1) * @per_page
    end
  end
end
