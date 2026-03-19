FactoryBot.define do
  factory :adventure do
    association :user
    association :story

    dm_settings   { {} }
    directed_dm   { false }
    discarded_at  { nil }
    story_summary { "The adventure has just begun." }
  end
end
