# frozen_string_literal: true

class EmailVerificationsController < ApplicationController
  skip_before_action :require_login, only: :show

  def show
    user = User.find_signed(params[:token], purpose: :email_verification)

    if user.nil?
      redirect_to root_path(verification: "invalid")
      return
    end

    user.update!(email_verified_at: Time.current) unless user.email_verified?
    redirect_to root_path(verification: "ok")
  end
end
