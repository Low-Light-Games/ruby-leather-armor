FactoryBot.define do
  factory :adventure_sheet do
    association :adventure

    name             { "Aldric Stonebrow" }
    character_class  { "Fighter" }
    race             { "Human" }
    level            { 1 }
    strength         { 14 }
    dexterity        { 12 }
    constitution     { 13 }
    intelligence     { 10 }
    wisdom           { 11 }
    charisma         { 8 }
    hp               { 12 }
    max_hp           { 12 }
  end
end
