module Admin
  class AiLogsController < ApplicationController
    before_action :require_admin

    PER_PAGE = 50

    def index
      @logs = AiLog.includes(:adventure)
                    .recent_first

      # Optional filters
      @logs = @logs.where(adventure_id: params[:adventure_id]) if params[:adventure_id].present?
      @logs = @logs.where(status: params[:status]) if params[:status].present?
      @logs = @logs.where(call_type: params[:call_type]) if params[:call_type].present?
      @logs = @logs.where(dm_service: params[:dm_service]) if params[:dm_service].present?

      @page = [params[:page].to_i, 1].max
      @total_count = @logs.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @logs = @logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      render layout: 'application'
    end

    def show
      @log = AiLog.find(params[:id])
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
