# frozen_string_literal: true

# Deterministic feature-flag lockdown for the playwright e2e environment.
#
# Two layers of safety so e2e runs never drift:
#
#   1. At boot, force every FeatureFlag row to `mode: "off"`. Keeps the admin
#      UI honest and prevents accidental DB-level toggles from a previous
#      session leaking into the next.
#
#   2. Override the readers on FeatureFlag (instance and class) to always
#      return false. Even if a row gets flipped mid-run (admin UI, console),
#      every code path that asks "is X enabled?" sees `false` until the
#      Rails process restarts.
#
# Loaded only in `Rails.env.playwright?`. Production / development / test
# behavior is untouched.

return unless Rails.env.playwright?

Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.data_source_exists?("feature_flags")
    drifted = FeatureFlag.where.not(mode: "off")
    if drifted.any?
      Rails.logger.warn(
        "[playwright] Forcing #{drifted.count} feature flag(s) to mode=off: " \
        "#{drifted.pluck(:key).inspect}"
      )
      drifted.update_all(mode: "off")
    end
  end

  FeatureFlag.class_eval do
    def enabled_for?(_user)
      false
    end

    def self.enabled_for?(_key, _user)
      false
    end
  end
end
