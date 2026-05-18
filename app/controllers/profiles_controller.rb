# frozen_string_literal: true

class ProfilesController < ApplicationController
  def update_email
    email = params[:email].to_s.strip.downcase

    if email.blank?
      render json: { error: "Email cannot be blank" }, status: :unprocessable_entity
      return
    end

    current_user.email = email

    if current_user.save
      render json: { email: current_user.email }
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
