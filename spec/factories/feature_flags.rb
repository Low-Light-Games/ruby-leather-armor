FactoryBot.define do
  factory :feature_flag do
    sequence(:key) { |n| "test_feature_#{n}" }
    enabled { false }

    trait :enabled do
      enabled { true }
    end
  end
end
