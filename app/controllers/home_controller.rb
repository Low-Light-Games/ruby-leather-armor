class HomeController < ApplicationController
  skip_before_action :require_login

  def index
    if current_user&.admin?
      redirect_to admin_play_logs_path
    else
      redirect_to sheets_path
    end
  end
end
