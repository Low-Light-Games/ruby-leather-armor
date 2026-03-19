require "rails_helper"

RSpec.describe FeatureFlag, type: :model do
  describe "validations" do
    subject { build(:feature_flag) }

    it { should validate_presence_of(:key) }
    it { should validate_uniqueness_of(:key) }
  end

  describe "factory" do
    it "builds a valid flag" do
      expect(build(:feature_flag)).to be_valid
    end
  end

  describe ".enabled?" do
    it "returns false when flag does not exist" do
      expect(FeatureFlag.enabled?(:nonexistent_flag)).to be false
    end

    it "returns false when flag exists but is disabled" do
      create(:feature_flag, key: "my_feature", enabled: false)
      expect(FeatureFlag.enabled?("my_feature")).to be false
    end

    it "returns true when flag is enabled" do
      create(:feature_flag, key: "active_feature", enabled: true)
      expect(FeatureFlag.enabled?("active_feature")).to be true
    end
  end
end
