class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_login
  skip_before_action :verify_authenticity_token, only: :google_oauth2

  def google_oauth2
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)

    if user&.persisted?
      session[:user_id] = user.id
      redirect_to request.env['omniauth.origin'] || root_path
    else
      redirect_to root_path, alert: "Google sign-in failed. Please try again."
    end
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message].to_s.humanize}"
  end
end
