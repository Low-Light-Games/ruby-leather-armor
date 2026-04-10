module Admin
  class PlayLogsController < BaseController

    PER_PAGE = 50
    RETRY_WINDOW = 5.minutes

    def index
      @show_usage = params[:show_usage] == "1"
      includes = [:adventure, :player_message]
      includes << :ai_usage_record if @show_usage

      @logs = PlayLog.includes(*includes).recent_first

      @logs = @logs.where(adventure_id: params[:adventure_id]) if params[:adventure_id].present?
      @logs = @logs.where(status: params[:status]) if params[:status].present?
      @logs = @logs.where(event_type: params[:event_type]) if params[:event_type].present?

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
      runs = PlayLog.where.not(registry_entry_uuid: [nil, ""])
                    .select("registry_entry_uuid, MIN(created_at) AS first_at, MAX(created_at) AS last_at, COUNT(*) AS step_count, MIN(adventure_id) AS adventure_id")
                    .group(:registry_entry_uuid)
                    .order("first_at DESC")

      @page = [params[:page].to_i, 1].max
      @total_count = PlayLog.where.not(registry_entry_uuid: [nil, ""]).distinct.count(:registry_entry_uuid)
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      runs = runs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      uuids = runs.map(&:registry_entry_uuid)
      logs_by_uuid = PlayLog.where(registry_entry_uuid: uuids)
                            .order(:created_at)
                            .group_by(&:registry_entry_uuid)

      registry_entries = PipelineRegistryEntry.where(registry_entry_uuid: uuids).index_by(&:registry_entry_uuid)

      msg_ids = logs_by_uuid.values.flatten.filter_map(&:player_message_id).uniq
      messages = AdventureMessage.where(id: msg_ids).index_by(&:id)

      @pipeline_runs = runs.map do |run|
        logs  = logs_by_uuid[run.registry_entry_uuid] || []
        msg   = logs.first && messages[logs.first.player_message_id]
        entry = registry_entries[run.registry_entry_uuid]

        Admin::PipelineRunPresenter.new(run, logs: logs, player_message: msg, registry_entry: entry).as_hash
      end

      detect_retries!(@pipeline_runs)

      render layout: 'admin'
    end

    def pipeline
      @active_nav = :pipelines
      @show_usage = params[:show_usage] == "1"
      includes = [:adventure]
      includes << :ai_usage_record if @show_usage

      @logs = PlayLog.where(registry_entry_uuid: params[:registry_entry_uuid])
                     .order(:created_at)
                     .includes(*includes)
      if @logs.empty?
        redirect_to pipelines_admin_play_logs_path, alert: "Pipeline run not found"
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
      @logs = PlayLog.where(registry_entry_uuid: @registry_entry_uuid)
                     .order(:created_at)
                     .includes(:ai_usage_record)

      if @logs.empty?
        redirect_to pipelines_admin_play_logs_path, alert: "Pipeline run not found"
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

    def detect_retries!(pipeline_runs)
      sorted = pipeline_runs.sort_by { |r| r[:first_at] }
      sorted.each_with_index do |run, idx|
        run[:retry_of] = nil
        next if idx == 0
        prev = sorted[idx - 1]
        next unless run[:adventure_id] && run[:adventure_id] == prev[:adventure_id]
        next unless run[:first_at] - prev[:first_at] < RETRY_WINDOW
        next unless run[:message_content].present? && prev[:message_content].present?
        next unless run[:message_content].strip == prev[:message_content].strip

        run[:retry_of] = prev[:retry_of] || prev[:registry_entry_uuid]
      end
    end
  end
end
