class User < ApplicationRecord
  has_secure_password

  has_many :sheets, dependent: :destroy
  has_many :adventures, dependent: :destroy
  has_many :dm_logs, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end
