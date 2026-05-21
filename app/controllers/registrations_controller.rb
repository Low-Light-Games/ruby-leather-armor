# frozen_string_literal: true

class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: :create

  def create
    user = User.new(registration_params)

    if user.save
      absorb_pending_guest_into(user)
      session[:user_id] = user.id
      UserMailer.verify_email(user).deliver_later
      render json: { user: user_json(user.reload) }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    permitted = params.permit(:email, :handle, :password, :password_confirmation)
    permitted[:email] = permitted[:email]&.strip&.downcase
    permitted[:handle] = permitted[:handle].presence
    permitted
  end

  def user_json(user)
    SessionUserPresenter.new(user: user).to_h
  end
end
