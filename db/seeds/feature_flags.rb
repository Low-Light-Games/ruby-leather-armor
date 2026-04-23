# frozen_string_literal: true

# Idempotent: safe for db:seed on every deploy (e.g. preview). Not run via schema:load.
FeatureFlag.find_or_create_by!(key: "paying_users_allowed") do |f|
  f.enabled = false
  f.description = "When enabled, users can open plans, checkout, billing portal, and subscription success flows."
end
