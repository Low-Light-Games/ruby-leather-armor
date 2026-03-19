class User < ApplicationRecord
  has_secure_password validations: false

  has_many :sheets, dependent: :destroy
  has_many :adventures, dependent: :destroy
  has_many :dm_logs, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, on: :create, unless: :oauth_user?

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_initialize.tap do |user|
      user.email = auth.info.email
      user.provider = auth.provider
      user.uid = auth.uid
      user.save!
    end
  end

  def oauth_user?
    provider.present?
  end
end
