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
    source_kind  { "custom" }
    starter_key  { nil }

    trait :starter_rogue do
      name            { "Maren Ashwick" }
      character_class { "Rogue" }
      race            { "Human" }
      strength        { 10 }
      dexterity       { 17 }
      constitution    { 12 }
      intelligence    { 14 }
      wisdom          { 10 }
      charisma        { 8 }
      source_kind     { "starter" }
      starter_key     { "rogue" }
    end

    trait :starter_fighter do
      name            { "Aldric Vane" }
      character_class { "Fighter" }
      race            { "Human" }
      strength        { 17 }
      dexterity       { 13 }
      constitution    { 14 }
      intelligence    { 10 }
      wisdom          { 12 }
      charisma        { 8 }
      source_kind     { "starter" }
      starter_key     { "fighter" }
    end
  end
end
