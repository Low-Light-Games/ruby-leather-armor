class User < ApplicationRecord
  has_secure_password validations: false

  TIERS = %w[free paid].freeze

  # Monthly cost cap in microdollars ($1 = 1,000,000 microdollars).
  # Defined in tier_limits.yml at the project root.
  TIER_LIMITS = YAML.load_file(Rails.root.join("tier_limits.yml"))
                    .dig("tiers")
                    .transform_values { |v| v["monthly_limit_microdollars"] }
                    .freeze

  has_many :sheets, dependent: :destroy
  has_many :adventures, dependent: :destroy
  has_many :ai_usage_records, dependent: :nullify

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, on: :create, unless: :oauth_user?
  validates :tier, inclusion: { in: TIERS }

  def self.from_omniauth(auth)
    user = where(provider: auth.provider, uid: auth.uid).first_or_initialize
    
    if user.new_record?
      user.email = auth.info.email
      user.provider = auth.provider
      user.uid = auth.uid
      user.save!
    end
    
    user
  end

  def oauth_user?
    provider.present?
  end

  def free?
    tier == "free"
  end

  def paid?
    tier == "paid"
  end

  def monthly_usage_limit
    TIER_LIMITS[tier]
  end

  def monthly_usage_microdollars
    ai_usage_records
      .where("created_at >= ?", Time.current.beginning_of_month)
      .sum(:total_cost_microdollars)
  end

  def usage_limit_reached?
    limit = monthly_usage_limit
    return false if limit.nil?

    monthly_usage_microdollars >= limit
  end

  def usage_percentage
    limit = monthly_usage_limit
    return 0.0 if limit.nil? || limit.zero?

    [(monthly_usage_microdollars.to_f / limit * 100).round(1), 100.0].min
  end
end
