module Admin
  class AiLogsController < ApplicationController
    before_action :require_admin

    PER_PAGE = 50
    TERMINAL_STEPS = %w[narrate dm_query edge_pipeline].freeze
    ERROR_STATUSES = %w[api_error parse_error token_budget_exceeded logging_error].freeze
    RETRY_WINDOW = 5.minutes

    def index
      @logs = AiLog.includes(:adventure, :player_message)
                    .recent_first

      @logs = @logs.where(adventure_id: params[:adventure_id]) if params[:adventure_id].present?
      @logs = @logs.where(status: params[:status]) if params[:status].present?
      @logs = @logs.where(call_type: params[:call_type]) if params[:call_type].present?

      @page = [params[:page].to_i, 1].max
      @total_count = @logs.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @logs = @logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      render layout: 'application'
    end

    def show
      @log = AiLog.includes(:player_message).find(params[:id])
      render layout: 'application'
    end

    def pipelines
      runs = AiLog.where.not(pipeline_run_id: [nil, ""])
                  .select("pipeline_run_id, MIN(created_at) AS first_at, MAX(created_at) AS last_at, COUNT(*) AS step_count, MIN(adventure_id) AS adventure_id")
                  .group(:pipeline_run_id)
                  .order("first_at DESC")

      @page = [params[:page].to_i, 1].max
      @total_count = AiLog.where.not(pipeline_run_id: [nil, ""]).distinct.count(:pipeline_run_id)
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      runs = runs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      run_ids = runs.map(&:pipeline_run_id)
      logs_by_run = AiLog.where(pipeline_run_id: run_ids)
                         .order(:created_at)
                         .group_by(&:pipeline_run_id)

      pipeline_run_records = PipelineRun.where(pipeline_run_id: run_ids).index_by(&:pipeline_run_id)

      msg_ids = logs_by_run.values.flatten.filter_map(&:player_message_id).uniq
      messages = AdventureMessage.where(id: msg_ids).index_by(&:id)

      @pipeline_runs = runs.map do |run|
        logs = logs_by_run[run.pipeline_run_id] || []
        first_log = logs.first
        msg = first_log && messages[first_log.player_message_id]
        pr = pipeline_run_records[run.pipeline_run_id]

        status = if pr
                   pr.status
                 else
                   step_types = logs.map(&:call_type)
                   has_error = logs.any? { |l| l.status.in?(ERROR_STATUSES) }
                   has_terminal = step_types.any? { |t| TERMINAL_STEPS.include?(t) }
                   if has_error && !has_terminal then "errored"
                   elsif has_error                then "partial"
                   elsif has_terminal             then "complete"
                   else                                "incomplete"
                   end
                 end

        {
          pipeline_run_id: run.pipeline_run_id,
          adventure_id: run.adventure_id,
          first_at: run.first_at,
          last_at: run.last_at,
          step_count: run.step_count,
          message_content: msg&.content || first_log&.player_message_content,
          logs: logs,
          status: status,
          pipeline_run: pr
        }
      end

      detect_retries!(@pipeline_runs)

      render layout: 'application'
    end

    def pipeline
      @logs = AiLog.where(pipeline_run_id: params[:pipeline_run_id])
                   .order(:created_at)
                   .includes(:adventure)
      if @logs.empty?
        redirect_to pipelines_admin_ai_logs_path, alert: "Pipeline run not found"
        return
      end
      @adventure = @logs.first&.adventure
      first_log = @logs.first
      @player_message = first_log.player_message
      @player_message_content = @player_message&.content || first_log.player_message_content
      @pipeline_run_id = params[:pipeline_run_id]
      @pipeline_run = PipelineRun.find_by(pipeline_run_id: @pipeline_run_id)

      render layout: 'application'
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end

    # Groups consecutive pipelines that share adventure + similar player message
    # within a time window, marking later entries as retries.
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

        run[:retry_of] = prev[:retry_of] || prev[:pipeline_run_id]
      end
    end
  end
end
