# frozen_string_literal: true

# Loads moderation settings from config/moderation.yml at boot.
# Mirrors the pattern of User::TIER_LIMITS (tier_limits.yml).
#
# Usage: ModerationConfig.instance.enabled?
#        ModerationConfig.instance.max_strikes
#        ModerationConfig.instance.default_response
class ModerationConfig
  CONFIG = YAML.load_file(Rails.root.join("config/moderation.yml"))
                .dig("moderation")
                .freeze

  def self.instance
    @instance ||= new
  end

  def enabled?
    CONFIG["enabled"]
  end

  def max_strikes
    CONFIG["max_strikes"]
  end

  def default_response
    CONFIG["default_response"]
  end
end
