class User < ApplicationRecord
  has_secure_password validations: false

  ONBOARDING_STATES = %w[new in_progress completed].freeze

  has_many :sheets, dependent: :destroy
  has_many :adventures, dependent: :destroy
  has_many :ai_usage_records, dependent: :nullify
  has_many :moderation_events, dependent: :destroy
  has_one :stripe_profile, class_name: "UserStripeProfile", dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, on: :create, unless: :oauth_user?
  validates :onboarding_state, inclusion: { in: ONBOARDING_STATES }

  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    user ||= find_by(email: auth.info.email)
    user ||= new

    user.provider = auth.provider
    user.uid = auth.uid
    user.email = auth.info.email
    user.save! if user.new_record? || user.changed?
    user
  end

  def oauth_user?
    provider.present?
  end

  def free?
    plan_key == "free"
  end

  def paid?
    !free?
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

  def usage_limit_reached?
    return false if admin?

    limit = monthly_usage_limit
    return false if limit.nil?

    monthly_usage_tokens >= limit
  end

  def usage_percentage
    limit = monthly_usage_limit
    return 0.0 if limit.nil? || limit.zero?

    [(monthly_usage_tokens.to_f / limit * 100).round(1), 100.0].min
  end

  def banned?
    banned
  end

  def trusted?
    trusted
  end
end
