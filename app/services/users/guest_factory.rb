# frozen_string_literal: true

module Users
  class GuestFactory
    def self.salt
      Rails.application.credentials.guest_ip_salt.presence || ENV["GUEST_IP_SALT"].presence
    end

    def self.enabled?
      salt.present?
    end

    def self.hash_ip(ip)
      return nil if ip.blank?

      key = salt
      return nil if key.blank?

      Digest::SHA256.hexdigest("#{key}:#{ip}")
    end

    def self.find_for_ip(ip)
      hash = hash_ip(ip)
      return nil if hash.blank?

      User.find_by(guest_ip_hash: hash)
    end

    def self.find_or_create!(ip:)
      hash = hash_ip(ip)
      return nil if hash.blank?

      existing = User.find_by(guest_ip_hash: hash)
      return existing if existing

      User.create!(
        guest_ip_hash: hash,
        email: "guest-#{SecureRandom.uuid}#{User::PLACEHOLDER_EMAIL_DOMAIN}",
        guest_created_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      User.find_by(guest_ip_hash: hash)
    end
  end
end
