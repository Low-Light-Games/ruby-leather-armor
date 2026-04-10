# frozen_string_literal: true

require "rails_helper"

RSpec.describe CharacterStats::EncumbranceCalculator do
  # Pure calculation class — no DB required for most examples.

  let(:no_items)   { [] }
  let(:no_equip)   { { speed_30: nil, speed_20: nil } }
  let(:base_speed) { 30 }

  def build_calc(items: no_items, str_score: 10, size: "Medium", coin_count: 0)
    described_class.new(items, str_score: str_score, size: size, coin_count: coin_count)
  end

  describe "#compute" do
    it "returns the expected keys" do
      result = build_calc.compute(base_speed: base_speed, equip: no_equip)
      expect(result).to include(:total_weight, :carry_capacity, :encumbrance, :enc_limits, :effective_speed)
    end

    it "returns light encumbrance for an empty-handed character" do
      result = build_calc.compute(base_speed: base_speed, equip: no_equip)
      expect(result[:encumbrance]).to eq(:light)
      expect(result[:total_weight]).to eq(0.0)
    end

    it "returns carry_capacity as a hash with light/medium/heavy keys" do
      result = build_calc.compute(base_speed: base_speed, equip: no_equip)
      expect(result[:carry_capacity]).to include(:light, :medium, :heavy)
    end
  end

  describe "encumbrance tiers" do
    let(:str_10_caps) { CharacterStats::GameRules::CARRY_CAPACITY[10] }  # [33, 66, 100]

    it "is :light when weight is within the light limit" do
      result = build_calc(str_score: 10, coin_count: 0).compute(base_speed: base_speed, equip: no_equip)
      expect(result[:encumbrance]).to eq(:light)
    end

    it "is :medium when weight exceeds light but not medium" do
      # STR 10: light = 33, medium = 66 — 50 coins = 1 lb, so 1700 coins ≈ 34 lb
      result = build_calc(str_score: 10, coin_count: 1700).compute(base_speed: base_speed, equip: no_equip)
      expect(result[:encumbrance]).to eq(:medium)
    end
  end

  describe "effective speed" do
    it "returns base_speed when unencumbered and no armor" do
      result = build_calc.compute(base_speed: 30, equip: no_equip)
      expect(result[:effective_speed]).to eq(30)
    end

    it "reduces speed to 20 when medium-encumbered with base 30" do
      result = build_calc(str_score: 10, coin_count: 1700).compute(base_speed: 30, equip: no_equip)
      expect(result[:encumbrance]).to eq(:medium)
      expect(result[:effective_speed]).to eq(20)
    end

    it "uses armor speed table when armor sets a reduced speed" do
      equip_with_armor = { speed_30: 20, speed_20: nil }
      result = build_calc.compute(base_speed: 30, equip: equip_with_armor)
      expect(result[:effective_speed]).to eq(20)
    end
  end

  describe "Small race modifier" do
    it "carries 3/4 of Medium capacity" do
      medium_light = CharacterStats::GameRules::CARRY_CAPACITY[10][0]  # 33
      small_result = build_calc(str_score: 10, size: "Small").compute(base_speed: 20, equip: no_equip)
      expect(small_result[:carry_capacity][:light]).to eq((medium_light * 0.75).floor)
    end
  end
end
