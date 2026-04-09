FactoryBot.define do
  factory :adventure_message do
    association :adventure

    role         { "player" }
    content      { "I open the door carefully." }
    message_type { "narrative" }
    metadata     { {} }

    trait :player do
      role { "player" }
    end

    trait :dm do
      role         { "dm" }
      content      { "The door swings open to reveal a dark corridor." }
      message_type { "narrative" }
    end

    trait :roll_request do
      role         { "dm" }
      message_type { "roll_request" }
      content      { "Roll Perception DC 12." }
      metadata     { { "rolls" => [{ "type" => "perception", "dc" => 12 }], "registry_entry_uuid" => "test-run-id" } }
    end

    trait :system do
      role         { "system" }
      message_type { "narrative" }
      content      { "Adventure started." }
    end
  end
end
