module Admin
  class AiLogsController < ApplicationController
    before_action :require_admin

    PER_PAGE = 50

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
      runs = AiLog.where.not(player_message_id: nil)
                  .select("player_message_id, MIN(created_at) AS first_at, MAX(created_at) AS last_at, COUNT(*) AS step_count, adventure_id")
                  .group(:player_message_id, :adventure_id)
                  .order("first_at DESC")

      @page = [params[:page].to_i, 1].max
      @total_count = AiLog.where.not(player_message_id: nil).distinct.count(:player_message_id)
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      runs = runs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      msg_ids = runs.map(&:player_message_id)
      @messages = AdventureMessage.where(id: msg_ids).index_by(&:id)

      logs_by_msg = AiLog.where(player_message_id: msg_ids)
                         .order(:created_at)
                         .group_by(&:player_message_id)

      @pipeline_runs = runs.map do |run|
        logs = logs_by_msg[run.player_message_id] || []
        {
          player_message_id: run.player_message_id,
          adventure_id: run.adventure_id,
          first_at: run.first_at,
          last_at: run.last_at,
          step_count: run.step_count,
          message: @messages[run.player_message_id],
          logs: logs,
          has_error: logs.any? { |l| l.status.in?(%w[api_error parse_error token_budget_exceeded]) },
          has_fallback: logs.any? { |l| l.status == "parse_fallback" }
        }
      end

      render layout: 'application'
    end

    def pipeline
      @player_message = AdventureMessage.find(params[:player_message_id])
      @logs = AiLog.where(player_message_id: @player_message.id)
                   .order(:created_at)
                   .includes(:adventure)
      @adventure = @logs.first&.adventure

      render layout: 'application'
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end
  end
end
