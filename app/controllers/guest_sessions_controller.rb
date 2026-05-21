# frozen_string_literal: true

class GuestSessionsController < ApplicationController
  skip_before_action :require_login, only: :create

  def create
    unless Users::GuestFactory.enabled?
      render json: { error: "Guest sessions are not enabled" }, status: :service_unavailable
      return
    end

    if session[:user_id].present? && (authed = User.find_by(id: session[:user_id]))
      render json: { user: user_json(authed) }
      return
    end

    user = Users::GuestFactory.find_or_create!(ip: request.remote_ip)

    if user
      render json: { user: user_json(user) }, status: :created
    else
      render json: { error: "Unable to start guest session" }, status: :unprocessable_entity
    end
  end

  private

  def user_json(user)
    SessionUserPresenter.new(user: user).to_h
  end
end
