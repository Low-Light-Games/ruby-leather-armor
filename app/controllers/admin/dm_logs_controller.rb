module Admin
  class DmLogsController < ApplicationController
    before_action :require_admin

    PER_PAGE = 50

    def index
      @logs = DmLog.includes(:adventure, :user)
                    .recent_first

      # Optional filters
      @logs = @logs.where(adventure_id: params[:adventure_id]) if params[:adventure_id].present?
      @logs = @logs.where(user_id: params[:user_id]) if params[:user_id].present?

      @page = [params[:page].to_i, 1].max
      @total_count = @logs.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @logs = @logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      render layout: 'application'
    end

    def show
      @log = DmLog.includes(:adventure, :user).find(params[:id])
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
