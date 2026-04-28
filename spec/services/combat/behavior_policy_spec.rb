# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::BehaviorPolicy do
  describe 'defaults' do
    let(:policy) { described_class.new({}) }

    it 'approaches by default' do
      expect(policy.approach_when_out_of_reach?).to be(true)
    end

    it 'does not flee by default' do
      expect(policy.flee_at_hp_pct).to eq(0.0)
    end

    it 'has no preferred attacks' do
      expect(policy.preferred_attacks).to eq([])
    end
  end

  describe 'preferred_attacks' do
    let(:policy) do
      described_class.new(
        'preferred_attacks' => [
          { 'name' => 'javelin',   'min_range_squares' => 4 },
          { 'name' => 'longsword', 'max_range_squares' => 1 }
        ]
      )
    end

    it 'matches javelin at long range only' do
      javelin = policy.preferred_attacks.first
      expect(javelin.matches_distance?(5)).to be(true)
      expect(javelin.matches_distance?(2)).to be(false)
    end

    it 'matches longsword in melee only' do
      longsword = policy.preferred_attacks.last
      expect(longsword.matches_distance?(1)).to be(true)
      expect(longsword.matches_distance?(2)).to be(false)
    end
  end

  describe 'morale' do
    it 'reads flee_at_hp_pct' do
      policy = described_class.new('morale' => { 'flee_at_hp_pct' => 0.2 })
      expect(policy.flee_at_hp_pct).to eq(0.2)
    end
  end
end
