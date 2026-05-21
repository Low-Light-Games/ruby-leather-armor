module Admin
  class PlayLogsController < BaseController

    PER_PAGE = 50
    RETRY_WINDOW = 5.minutes

    def index
      @show_usage = params[:show_usage] == "1"
      includes = [:adventure, :player_message]
      includes << :ai_usage_record if @show_usage

      @logs = PlayLog.includes(*includes).recent_first

      @logs = @logs.for_adventure(params[:adventure_id]) if params[:adventure_id].present?
      @logs = @logs.with_status(params[:status]) if params[:status].present?
      @logs = @logs.with_event_type(params[:event_type]) if params[:event_type].present?

      @page = [params[:page].to_i, 1].max
      @total_count = @logs.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @logs = @logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      render layout: 'admin'
    end

    def show
      @log = PlayLog.includes(:player_message).find(params[:id])
      render layout: 'admin'
    end

    def pipelines
      @active_nav = :pipelines
      @page = [params[:page].to_i, 1].max
      pipeline_query = Admin::PlayLogPipelineQuery.new(page: @page, per_page: PER_PAGE)
      @total_count = pipeline_query.total_count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      aggregates = pipeline_query.paged_aggregates

      uuids = aggregates.map(&:registry_entry_uuid)
      logs_by_uuid = PlayLog.for_registry_entry_uuids(uuids)
                            .order(:created_at)
                            .group_by(&:registry_entry_uuid)

      registry_entries = PipelineRegistryEntry.for_registry_entry_uuids(uuids)
                                               .includes(adventure: :user)
                                               .index_by(&:registry_entry_uuid)

      msg_ids = logs_by_uuid.values.flatten.filter_map(&:player_message_id).uniq
      messages = AdventureMessage.where(id: msg_ids).index_by(&:id)

      @registry_entry_summaries = aggregates.map do |aggregate|
        logs  = logs_by_uuid[aggregate.registry_entry_uuid] || []
        player_message = first_player_message_for_logs(logs, messages)
        entry = registry_entries[aggregate.registry_entry_uuid]

        Admin::RegistryEntryPresenter.new(aggregate, logs: logs, player_message: player_message, registry_entry: entry).as_hash
      end

      detect_retries!(@registry_entry_summaries)

      render layout: 'admin'
    end

    def pipeline
      @active_nav = :pipelines
      @show_usage = params[:show_usage] == "1"
      includes = [:adventure]
      includes << :ai_usage_record if @show_usage

      @logs = PlayLog.with_registry_entry_uuid(params[:registry_entry_uuid])
                     .order(:created_at)
                     .includes(*includes)
      if @logs.empty?
        redirect_to pipelines_admin_play_logs_path, alert: "Pipeline entry not found"
      return
    end
    @adventure = @logs.first&.adventure
      first_log = @logs.first
      @player_message = first_log.player_message
      @player_message_content = @player_message&.content || first_log.player_message_content
      @registry_entry_uuid = params[:registry_entry_uuid]
      @registry_entry = PipelineRegistryEntry.find_by(registry_entry_uuid: @registry_entry_uuid)

      render layout: 'admin'
    end

    def export_pipeline
      @registry_entry_uuid = params[:registry_entry_uuid]
      @logs = PlayLog.with_registry_entry_uuid(@registry_entry_uuid)
                     .order(:created_at)
                     .includes(:ai_usage_record)

      if @logs.empty?
        redirect_to pipelines_admin_play_logs_path, alert: "Pipeline entry not found"
        return
      end

      @registry_entry = PipelineRegistryEntry.find_by(registry_entry_uuid: @registry_entry_uuid)
      @adventure = @logs.first&.adventure
      @player_message_content = @logs.first&.player_message&.content || @logs.first&.player_message_content

      send_data render_to_string("pipeline_export", formats: [:text], layout: false),
                filename: "pipeline-#{@registry_entry_uuid}.log",
                type: "text/plain",
                disposition: "attachment"
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end

    def detect_retries!(summaries)
      sorted = summaries.sort_by { |s| s[:first_at] }
      sorted.each_with_index do |summary, idx|
        summary[:retry_of] = nil
        next if idx == 0

        previous_summary = sorted[idx - 1]
        next unless retry_candidate_pair?(summary, previous_summary)

        summary[:retry_of] = previous_summary[:retry_of] || previous_summary[:registry_entry_uuid]
      end
    end

    def first_player_message_for_logs(logs, messages_by_id)
      first_player_message_id = logs.first&.player_message_id
      messages_by_id[first_player_message_id]
    end

    def retry_candidate_pair?(summary, previous_summary)
      same_adventure?(summary, previous_summary) &&
        started_within_retry_window?(summary, previous_summary) &&
        same_player_message_content?(summary, previous_summary)
    end

    def same_adventure?(summary, previous_summary)
      summary[:adventure_id].present? && summary[:adventure_id] == previous_summary[:adventure_id]
    end

    def started_within_retry_window?(summary, previous_summary)
      summary[:first_at] - previous_summary[:first_at] < RETRY_WINDOW
    end

    def same_player_message_content?(summary, previous_summary)
      summary[:message_content].present? &&
        previous_summary[:message_content].present? &&
        summary[:message_content].strip == previous_summary[:message_content].strip
    end
  end
end
