FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "adventurer#{n}@example.com" }
    provider { "google_oauth2" }
    sequence(:uid) { |n| "google_uid_#{n}" }
    admin { false }

    trait :admin do
      admin { true }
      sequence(:email) { |n| "admin#{n}@example.com" }
    end

    # Non-OAuth user (password auth)
    trait :password_auth do
      provider { nil }
      uid { nil }
      password { "password123" }
    end
  end
end
