class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_login
  skip_before_action :verify_authenticity_token, only: :google_oauth2

  def google_oauth2
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)

    if user&.persisted?
      session[:user_id] = user.id
      # APP_URL is the canonical player app URL (https://app.leatherarmor.io).
      # Falls back to app_path (/app) for local development without the env var.
      redirect_to ENV.fetch("APP_URL", app_path)
    else
      redirect_to root_path, alert: "Google sign-in failed. Please try again."
    end
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message].to_s.humanize}"
  end
end
