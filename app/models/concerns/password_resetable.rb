# frozen_string_literal: true

module PasswordResetable
  extend ActiveSupport::Concern

  PASSWORD_RESET_TOKEN_TTL = 30.minutes

  def generate_password_reset!
    update!(
      password_reset_token: SecureRandom.urlsafe_base64(32),
      password_reset_sent_at: Time.current
    )
  end

  def password_reset_valid?
    password_reset_sent_at.present? && password_reset_sent_at > PASSWORD_RESET_TOKEN_TTL.ago
  end

  def clear_password_reset!
    update!(password_reset_token: nil, password_reset_sent_at: nil)
  end
end
