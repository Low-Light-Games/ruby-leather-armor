# frozen_string_literal: true

FactoryBot.define do
  factory :adventure_loop do
    association :adventure
    registry_entry_uuid { SecureRandom.uuid }
    sequence_index      { 0 }
    status              { "pending" }
    tags                { {} }
    data                { {} }
    timeline            { [] }
  end
end
