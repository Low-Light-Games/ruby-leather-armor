# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlag do
  describe ".enabled_for?" do
    let(:user) { create(:user) }

    it "returns false when no flag with the key exists" do
      expect(described_class.enabled_for?("missing_flag", user)).to be(false)
    end

    it "returns false when the flag is mode=off" do
      create(:feature_flag, key: "x", mode: "off")
      expect(described_class.enabled_for?("x", user)).to be(false)
    end

    it "returns true when the flag is mode=on" do
      create(:feature_flag, key: "x", mode: "on")
      expect(described_class.enabled_for?("x", user)).to be(true)
    end

    it "returns true for a granular flag when the user is in the list" do
      create(:feature_flag, :granular, key: "x", granular_user_ids: [user.id])
      expect(described_class.enabled_for?("x", user)).to be(true)
    end

    it "returns false for a granular flag when the user is not in the list" do
      other_user = create(:user)
      create(:feature_flag, :granular, key: "x", granular_user_ids: [other_user.id])
      expect(described_class.enabled_for?("x", user)).to be(false)
    end

    it "returns true for a modulo flag when the user's id matches an on-remainder" do
      create(:feature_flag, :modulo, key: "x", modulo_divisor: 2, modulo_on_remainders: [user.id % 2])
      expect(described_class.enabled_for?("x", user)).to be(true)
    end

    it "returns false for a modulo flag when the user's id does not match" do
      create(:feature_flag, :modulo, key: "x", modulo_divisor: 2,
                                     modulo_on_remainders: [(user.id + 1) % 2])
      expect(described_class.enabled_for?("x", user)).to be(false)
    end

    it "returns false for a bucketed flag when the user is nil" do
      create(:feature_flag, :granular, key: "x", granular_user_ids: [1, 2, 3])
      expect(described_class.enabled_for?("x", nil)).to be(false)
    end
  end

  describe "#enabled_for? — modulo rollout shapes" do
    let(:flag) { build(:feature_flag, :modulo, modulo_divisor: 10, modulo_on_remainders: [0]) }

    it "treats divisor=10 + on_remainders=[0] as a 10% rollout (id 10 ON, id 11 OFF)" do
      expect(flag.enabled_for?(double("User", id: 10))).to be(true)
      expect(flag.enabled_for?(double("User", id: 11))).to be(false)
    end

    it "treats divisor=10 + on_remainders=[0..2] as a 30% rollout" do
      flag.modulo_on_remainders = [0, 1, 2]
      expect(flag.enabled_for?(double("User", id: 10))).to be(true)
      expect(flag.enabled_for?(double("User", id: 12))).to be(true)
      expect(flag.enabled_for?(double("User", id: 13))).to be(false)
    end
  end

  describe "validations" do
    it "rejects an unknown mode" do
      flag = build(:feature_flag, mode: "weird")
      expect(flag).not_to be_valid
      expect(flag.errors[:mode]).to be_present
    end

    it "requires a bucketing_strategy when mode=bucketed" do
      flag = build(:feature_flag, mode: "bucketed", bucketing_strategy: nil)
      expect(flag).not_to be_valid
      expect(flag.errors[:bucketing_strategy]).to be_present
    end

    it "rejects modulo_divisor outside 2..10" do
      flag = build(:feature_flag, :modulo, modulo_divisor: 11, modulo_on_remainders: [0])
      expect(flag).not_to be_valid
      expect(flag.errors[:modulo_divisor]).to be_present
    end

    it "rejects modulo_on_remainders that exceed divisor-1" do
      flag = build(:feature_flag, :modulo, modulo_divisor: 2, modulo_on_remainders: [2])
      expect(flag).not_to be_valid
      expect(flag.errors[:modulo_on_remainders]).to be_present
    end

    it "accepts a granular flag with no users (effectively OFF for everyone)" do
      flag = build(:feature_flag, :granular, granular_user_ids: [])
      expect(flag).to be_valid
    end
  end
end
