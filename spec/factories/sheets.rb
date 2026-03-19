FactoryBot.define do
  factory :sheet do
    association :user

    sequence(:name) { |n| "Aldric Stonebrow #{n}" }
    character_class { "Fighter" }
    race            { "Human" }
    level           { 1 }

    strength     { 14 }
    dexterity    { 12 }
    constitution { 13 }
    intelligence { 10 }
    wisdom       { 11 }
    charisma     { 8 }
  end
end
