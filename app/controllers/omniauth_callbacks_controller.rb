# frozen_string_literal: true

class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_login
  skip_before_action :verify_authenticity_token, only: :callback

  def callback
    auth = request.env["omniauth.auth"]

    unless auth
      ApplicationErrorReporter.notify(
        NoMethodError.new("omniauth.auth missing in callback"),
        context: {
          provider: params[:provider],
          request_path: request.path,
          request_query_parameters: request.query_parameters,
          omniauth_error: params[:error],
          omniauth_error_description: params[:error_description],
          request_id: request.request_id
        }
      )
      redirect_to root_path, alert: "Sign-in failed. Please try again."
      return
    end

    existing_user = User.find_by(provider: auth.provider, uid: auth.uid) ||
                    (auth.info.email.present? && User.find_by(email: auth.info.email))
    user = User.from_omniauth(auth)

    if user&.persisted?
      absorb_pending_guest_into(user)
      session[:user_id] = user.id
      session[:oauth_new_signup] = existing_user.nil?
      session[:email_prompt] = true if user.placeholder_email?
      redirect_to request.env["omniauth.origin"] || root_path
    else
      session.delete(:oauth_new_signup)
      session.delete(:email_prompt)
      redirect_to root_path, alert: "Sign-in failed. Please try again."
    end
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message].to_s.humanize}"
  end
end
