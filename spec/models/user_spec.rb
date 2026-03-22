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

  describe "TIER_LIMITS" do
    it "loads from tier_limits.yml with values for all tiers" do
      expect(User::TIER_LIMITS.keys).to match_array(User::TIERS)
    end

    it "free tier has a lower limit than paid" do
      expect(User::TIER_LIMITS["free"]).to be < User::TIER_LIMITS["paid"]
    end

    it "all limits are positive integers" do
      User::TIER_LIMITS.each_value do |limit|
        expect(limit).to be_a(Integer).and be_positive
      end
    end
  end

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google_uid_123",
        info: OmniAuth::AuthHash::InfoHash.new(email: "user@example.com")
      )
    end

    it "creates a new user on first login" do
      expect { User.from_omniauth(auth) }.to change(User, :count).by(1)
    end

    it "returns the same user on subsequent logins" do
      user = User.from_omniauth(auth)
      expect(User.from_omniauth(auth)).to eq(user)
    end

    it "does not persist the record on subsequent logins with no changes" do
      user = User.from_omniauth(auth)
      expect(user).not_to receive(:save!)
      User.from_omniauth(auth)
    end

    it "does not create a duplicate on subsequent logins" do
      User.from_omniauth(auth)
      expect { User.from_omniauth(auth) }.not_to change(User, :count)
    end

    it "links an existing email/password account instead of raising" do
      existing = create(:user, :password_auth, email: "user@example.com")
      expect { User.from_omniauth(auth) }.not_to change(User, :count)
      expect(existing.reload.provider).to eq("google_oauth2")
      expect(existing.reload.uid).to eq("google_uid_123")
    end
  end

  describe "#usage_limit_reached?" do
    it "returns false when no AI usage has been recorded" do
      expect(create(:user).usage_limit_reached?).to be false
    end
  end
end
