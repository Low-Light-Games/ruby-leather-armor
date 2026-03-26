require "rails_helper"

RSpec.describe Adventure, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:story) }
    it { should have_many(:adventure_messages).dependent(:destroy) }
    it { should have_many(:adventure_sheets).dependent(:destroy) }
    it { should have_many(:play_logs).dependent(:nullify) }
  end

  describe "factory" do
    it "builds a valid adventure" do
      expect(build(:adventure)).to be_valid
    end
  end

  describe "#discarded?" do
    it "returns false when discarded_at is nil" do
      expect(build(:adventure, discarded_at: nil).discarded?).to be false
    end

    it "returns true when discarded_at is set" do
      expect(build(:adventure, discarded_at: 1.hour.ago).discarded?).to be true
    end
  end

  describe "#directed_dm?" do
    it "returns false by default" do
      expect(build(:adventure).directed_dm?).to be false
    end

    it "returns true when directed_dm is set" do
      expect(build(:adventure, directed_dm: true).directed_dm?).to be true
    end
  end

  describe "#skip_world_sanity_check?" do
    it "returns false by default" do
      expect(build(:adventure).skip_world_sanity_check?).to be false
    end

    it "returns true when skip_world_sanity_check is set" do
      expect(build(:adventure, skip_world_sanity_check: true).skip_world_sanity_check?).to be true
    end
  end
end
