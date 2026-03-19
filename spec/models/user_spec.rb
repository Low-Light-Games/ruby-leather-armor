require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { should have_many(:sheets).dependent(:destroy) }
    it { should have_many(:adventures).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
  end

  describe "factory" do
    it "builds a valid OAuth user" do
      expect(build(:user)).to be_valid
    end

    it "builds a valid admin user" do
      expect(build(:user, :admin)).to be_valid
    end
  end

  describe "#oauth_user?" do
    it "returns true when provider is set" do
      expect(build(:user, provider: "google_oauth2").oauth_user?).to be true
    end

    it "returns false when provider is blank" do
      expect(build(:user, provider: nil).oauth_user?).to be false
    end
  end
end
