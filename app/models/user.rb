class User < ApplicationRecord
  include PasswordResetable

  has_secure_password validations: false

  ONBOARDING_STATES = %w[new in_progress completed].freeze
  COMBAT_DICE_STRATEGIES = %w[client server].freeze
  PLACEHOLDER_EMAIL_DOMAIN = "@noreply.fake"

  GUEST_LIFETIME_TOKEN_CAP = 50_000
  EMAIL_VERIFICATION_GRACE_PERIOD = 7.days
  HANDLE_FORMAT = /\A[a-zA-Z0-9_]{3,32}\z/

  has_many :sheets, dependent: :destroy
  has_many :adventures, dependent: :destroy
  has_many :ai_usage_records, dependent: :nullify
  has_many :moderation_events, dependent: :destroy
  has_one :stripe_profile, class_name: "UserStripeProfile", dependent: :destroy

  scope :for_admin_index, lambda {
    includes(:stripe_profile)
      .order(created_at: :desc)
      .select(:id, :email, :admin, :banned, :banned_at, :trusted, :moderation_strikes, :created_at)
  }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, unless: :guest?
  validates :password, presence: true, on: :create, unless: :oauth_or_guest?
  validates :password, length: { minimum: 8 }, if: :password_length_validation_required?
  validates :password, confirmation: true, if: -> { password.present? }
  validates :handle, format: { with: HANDLE_FORMAT }, allow_nil: true
  validates :onboarding_state, inclusion: { in: ONBOARDING_STATES }
  validates :combat_dice_strategy, inclusion: { in: COMBAT_DICE_STRATEGIES }

  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    user ||= find_by(email: auth.info.email) if auth.info.email.present?
    user ||= new

    user.provider = auth.provider
    user.uid = auth.uid
    user.email = auth.info.email.presence || "#{SecureRandom.uuid}#{PLACEHOLDER_EMAIL_DOMAIN}"
    user.email_verified_at ||= Time.current if auth.info.email.present?
    user.save! if user.new_record? || user.changed?
    user
  end

  def oauth_user?
    provider.present?
  end

  def guest?
    guest_ip_hash.present?
  end

  def password_user?
    !guest? && !oauth_user? && password_digest.present?
  end

  def oauth_or_guest?
    oauth_user? || guest?
  end

  def placeholder_email?
    email.to_s.end_with?(PLACEHOLDER_EMAIL_DOMAIN)
  end

  def email_verified?
    email_verified_at.present?
  end

  def email_verification_required?
    return false if guest? || oauth_user? || email_verified?

    Time.current >= created_at + EMAIL_VERIFICATION_GRACE_PERIOD
  end

  def free?
    plan_key == "free"
  end

  def paid?
    !free?
  end

  def paid_or_admin?
    admin? || paid?
  end

  def plan_key
    stripe_profile&.effective_plan_key.presence || "free"
  end

  def monthly_usage_limit
    StripePlans.token_limit_for(plan_key)
  end

  def monthly_usage_tokens
    ai_usage_records
      .where("created_at >= ?", Time.current.beginning_of_month)
      .sum(:total_tokens)
  end

  def lifetime_usage_tokens
    ai_usage_records.sum(:total_tokens)
  end

  def current_usage_tokens
    guest? ? lifetime_usage_tokens : monthly_usage_tokens
  end

  def current_usage_limit
    guest? ? GUEST_LIFETIME_TOKEN_CAP : monthly_usage_limit
  end

  def usage_limit_reached?
    return false if admin?

    limit = current_usage_limit
    return false if limit.nil?

    current_usage_tokens >= limit
  end

  def usage_percentage
    limit = current_usage_limit
    return 0.0 if limit.nil? || limit.zero?

    [(current_usage_tokens.to_f / limit * 100).round(1), 100.0].min
  end

  def banned?
    banned
  end

  def password_length_validation_required?
    return false if Thread.current[:skip_user_password_length_validation]

    password.present?
  end

  def trusted?
    trusted
  end
end
