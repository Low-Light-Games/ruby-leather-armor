class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_login
  skip_before_action :verify_authenticity_token, only: :google_oauth2

  def google_oauth2
    auth = request.env["omniauth.auth"]
    existing_user = User.find_by(provider: auth.provider, uid: auth.uid) || User.find_by(email: auth.info.email)
    user = User.from_omniauth(auth)

    if user&.persisted?
      session[:user_id] = user.id
      session[:oauth_new_signup] = existing_user.nil?
      redirect_to request.env['omniauth.origin'] || root_path
    else
      session.delete(:oauth_new_signup)
      redirect_to root_path, alert: "Google sign-in failed. Please try again."
    end
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message].to_s.humanize}"
  end
end
