class HomeController < ApplicationController
  skip_before_action :require_login
  layout "frontpage"

  def index
  end

  def reddit
  end
end
