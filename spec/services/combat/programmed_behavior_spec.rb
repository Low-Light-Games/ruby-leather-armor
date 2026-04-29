# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::ProgrammedBehavior do
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

  describe '.for(creature)' do
    let(:user)      { create(:user, :password_auth) }
    let(:story)     { create(:story) }
    let(:adventure) { create(:adventure, user: user, story: story) }
    let(:creature) do
      CreatureSheet.create!(
        adventure: adventure,
        name: 'Goblin', creature_type: 'monster', origin: 'ai', attitude: 'hostile',
        level: 1, strength: 11, dexterity: 13, constitution: 12,
        intelligence: 10, wisdom: 9, charisma: 6,
        hp: 6, max_hp: 6,
        equipped_weapons: equipped_weapons,
        behavior_policy: stored_policy
      )
    end
    let(:equipped_weapons) { [] }
    let(:stored_policy)    { {} }

    context 'when a stored policy has preferred_attacks' do
      let(:stored_policy) { { 'preferred_attacks' => [{ 'name' => 'shortsword', 'max_range_squares' => 1 }] } }

      it 'uses the stored policy verbatim' do
        policy = described_class.for(creature)
        expect(policy.preferred_attacks.map(&:name)).to eq(['shortsword'])
      end
    end

    context 'when stored policy is empty' do
      let(:equipped_weapons) do
        [{ 'name' => 'longbow', 'weapon_type' => 'ranged' },
         { 'name' => 'longsword' }]
      end

      it 'derives one preferred attack per equipped weapon, range-tagged by weapon_type' do
        policy = described_class.for(creature)
        names = policy.preferred_attacks.map(&:name)
        expect(names).to contain_exactly('longbow', 'longsword')
        bow = policy.preferred_attacks.find { |p| p.name == 'longbow' }
        sword = policy.preferred_attacks.find { |p| p.name == 'longsword' }
        expect(bow.matches_distance?(5)).to be(true)
        expect(bow.matches_distance?(1)).to be(false)
        expect(sword.matches_distance?(1)).to be(true)
        expect(sword.matches_distance?(2)).to be(false)
      end

      it 'approaches by default in the derived policy' do
        expect(described_class.for(creature).approach_when_out_of_reach?).to be(true)
      end
    end

    context 'when there are no equipped weapons' do
      it 'falls back to a melee natural attack' do
        policy = described_class.for(creature)
        attack = policy.preferred_attacks.first
        expect(attack.name).to eq('natural attack')
        expect(attack.matches_distance?(1)).to be(true)
        expect(attack.matches_distance?(2)).to be(false)
      end
    end
  end
end
