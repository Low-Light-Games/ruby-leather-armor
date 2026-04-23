require "rails_helper"

RSpec.describe UserStripeProfile, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    subject(:profile) { described_class.new(user: create(:user)) }

    it { should validate_inclusion_of(:plan_key).in_array(StripePlans::PLAN_KEYS) }
  end
end
