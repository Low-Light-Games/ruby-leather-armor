class HomeController < ApplicationController
  skip_before_action :require_login
  layout "frontpage", only: [:index]

  def index
  end

  def app
    render layout: "application"
  end
end
