require "rails_helper"

RSpec.describe Story, type: :model do
  describe "associations" do
    it { should have_many(:adventures).dependent(:destroy) }
    it { should have_many(:story_locations).dependent(:destroy) }
    it { should have_many(:story_npcs).dependent(:destroy) }
    it { should have_many(:story_clues).dependent(:destroy) }
    it { should have_many(:story_milestones).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:preview) }
    it { should validate_presence_of(:premise) }
  end

  describe "factory" do
    it "builds a valid story" do
      expect(build(:story)).to be_valid
    end
  end

  describe "#discarded?" do
    it "returns false when discarded_at is nil" do
      expect(build(:story, discarded_at: nil).discarded?).to be false
    end

    it "returns true when discarded_at is set" do
      expect(build(:story, discarded_at: 1.hour.ago).discarded?).to be true
    end
  end
end
