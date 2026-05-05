# frozen_string_literal: true

# Idempotent feature-flag seeds. Adding a new flag here is the
# canonical way to make it visible in /admin/feature_flags. Existing
# flags' mode/bucketing config is preserved on re-seed.

FLAGS = [
  {
    key: "gamemaster_orchestrator",
    description: "Routes out-of-combat turns through Steps::GameMaster (reasoning-model orchestrator) instead of the legacy phase chain. First iteration emits narrative directly; tools land later."
  }
].freeze

FLAGS.each do |attrs|
  flag = FeatureFlag.find_or_initialize_by(key: attrs[:key])
  flag.description = attrs[:description]
  flag.mode ||= "off"
  if flag.changed?
    flag.save!
    puts "Seeded feature flag '#{flag.key}' (mode=#{flag.mode})"
  end
end
