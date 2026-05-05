FactoryBot.define do
  factory :feature_flag do
    sequence(:key) { |n| "test_feature_#{n}" }
    mode { "off" }

    trait :on do
      mode { "on" }
    end

    trait :granular do
      mode { "bucketed" }
      bucketing_strategy { "granular" }
      granular_user_ids { [] }
    end

    trait :modulo do
      mode { "bucketed" }
      bucketing_strategy { "modulo" }
      modulo_divisor { 2 }
      modulo_on_remainders { [1] }
    end
  end
end
