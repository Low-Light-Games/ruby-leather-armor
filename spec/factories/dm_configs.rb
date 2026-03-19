FactoryBot.define do
  factory :dm_config do
    settings { DmConfig::DEFAULTS.dup }
  end
end
