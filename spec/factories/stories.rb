FactoryBot.define do
  factory :story do
    sequence(:title) { |n| "The Lost Crypt #{n}" }
    preview { "A crumbling crypt rumoured to hold forgotten treasure — and things better left forgotten." }
    premise { "The party has been hired to clear a crypt of the undead that have begun troubling nearby villages." }
    discarded_at { nil }
  end
end
