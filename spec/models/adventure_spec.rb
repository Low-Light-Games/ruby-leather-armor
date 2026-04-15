require "rails_helper"

RSpec.describe Adventure, type: :model do
  include ActiveSupport::Testing::TimeHelpers

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

  describe "#ended?" do
    it "returns false when ended_at is nil" do
      expect(build(:adventure, ended_at: nil).ended?).to be false
    end

    it "returns true when ended_at is set" do
      expect(build(:adventure, ended_at: 1.hour.ago).ended?).to be true
    end
  end

  describe "#mark_ended!" do
    let(:adventure) { create(:adventure) }

    it "sets ended_at and end_reason once" do
      travel_to(Time.zone.parse("2026-04-15 12:00:00 UTC")) do
        expect(adventure.mark_ended!(reason: "player_death")).to be true
      end

      ended_at = adventure.reload.ended_at
      expect(ended_at).to be_present
      expect(adventure.end_reason).to eq("player_death")

      travel_to(Time.zone.parse("2026-04-15 13:00:00 UTC")) do
        expect(adventure.mark_ended!(reason: "adventure_complete")).to be false
      end

      adventure.reload
      expect(adventure.ended_at).to eq(ended_at)
      expect(adventure.end_reason).to eq("player_death")
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
