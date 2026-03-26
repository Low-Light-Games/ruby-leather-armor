FactoryBot.define do
  factory :adventure do
    association :user
    association :story

    dm_settings   { {} }
    directed_dm              { false }
    skip_world_sanity_check  { false }
    discarded_at  { nil }
    story_summary { "The adventure has just begun." }
  end
end
