# frozen_string_literal: true

class UserMailer < ApplicationMailer
  EMAIL_VERIFICATION_TOKEN_TTL = 14.days

  def verify_email(user)
    @user = user
    @verification_url = email_verification_url(
      token: user.signed_id(purpose: :email_verification, expires_in: EMAIL_VERIFICATION_TOKEN_TTL)
    )
    mail(to: @user.email, subject: "Verify your email — Leather Armor")
  end
end
