class LegalController < ApplicationController
  skip_before_action :require_login

  def index
    render layout: 'legal'
  end
end
