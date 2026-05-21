# frozen_string_literal: true

class PasswordResetsController < ApplicationController
  layout "legal", only: %i[edit update]
  skip_before_action :require_login

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user && !user.oauth_user? && !user.guest?
      user.generate_password_reset!
      UserMailer.password_reset(user).deliver_later
    end

    render json: { message: "If that email is in our system, a reset link is on its way." }
  end

  def edit
    @user = find_user_by_token
  end

  def update
    @user = find_user_by_token
    return unless @user

    if @user.update(password_params)
      @user.clear_password_reset!
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Password updated. You're signed in."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def find_user_by_token
    user = User.find_by(password_reset_token: params[:token])
    return user if user&.password_reset_valid?

    redirect_to root_path(reset: "invalid")
    nil
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
