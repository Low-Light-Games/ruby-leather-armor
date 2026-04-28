# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::Rules do
  def pos(token_id, x, y)
    Combat::Position.new(token_id: token_id, label: token_id, coordinates: { x: x, y: y })
  end

  describe '.flanking?' do
    let(:target) { pos('goblin', 5, 5) }

    it 'is true when an ally sits directly opposite (cardinal)' do
      attacker = pos('player', 4, 5)
      ally     = pos('fighter', 6, 5)
      expect(described_class.flanking?(attacker: attacker, target: target, allies: [ally])).to be(true)
    end

    it 'is true when an ally sits directly opposite (diagonal)' do
      attacker = pos('player', 4, 4)
      ally     = pos('fighter', 6, 6)
      expect(described_class.flanking?(attacker: attacker, target: target, allies: [ally])).to be(true)
    end

    it 'is false when the ally is not opposite' do
      attacker = pos('player', 4, 5)
      ally     = pos('fighter', 5, 6)
      expect(described_class.flanking?(attacker: attacker, target: target, allies: [ally])).to be(false)
    end

    it 'is false when the attacker is out of reach' do
      attacker = pos('player', 2, 5)
      ally     = pos('fighter', 8, 5)
      expect(described_class.flanking?(attacker: attacker, target: target, allies: [ally])).to be(false)
    end

    it 'is false when there are no allies' do
      attacker = pos('player', 4, 5)
      expect(described_class.flanking?(attacker: attacker, target: target, allies: [])).to be(false)
    end
  end

  describe '.aoo_threats_against' do
    it 'returns adjacent others as threats' do
      mover = pos('player', 5, 5)
      goblin = pos('goblin', 6, 5)
      far_orc = pos('orc', 9, 9)
      threats = described_class.aoo_threats_against(mover: mover, mover_from: mover, others: [goblin, far_orc])
      expect(threats.map { |t| t.position.token_id }).to eq(['goblin'])
    end

    it 'excludes self' do
      mover = pos('player', 5, 5)
      threats = described_class.aoo_threats_against(mover: mover, mover_from: mover, others: [mover])
      expect(threats).to be_empty
    end
  end

  describe '.cover_between' do
    it 'returns 0 when adjacent' do
      a = pos('player', 5, 5); t = pos('goblin', 6, 5)
      expect(described_class.cover_between(attacker: a, target: t, others: [])).to eq(0)
    end

    it 'returns +4 when an intervening creature sits on the straight line' do
      a = pos('player', 5, 5); t = pos('goblin', 9, 5)
      blocker = pos('orc', 7, 5)
      expect(described_class.cover_between(attacker: a, target: t, others: [blocker])).to eq(4)
    end

    it 'ignores attacker and target as their own blockers' do
      a = pos('player', 5, 5); t = pos('goblin', 9, 5)
      expect(described_class.cover_between(attacker: a, target: t, others: [a, t])).to eq(0)
    end
  end

  describe '.threatens?' do
    let(:attacker) { pos('player', 5, 5) }

    it 'is true for an adjacent square' do
      expect(described_class.threatens?(attacker: attacker, square: { x: 6, y: 5 })).to be(true)
    end

    it 'is false for a far square at default reach' do
      expect(described_class.threatens?(attacker: attacker, square: { x: 8, y: 5 })).to be(false)
    end

    it 'extends to 2 squares when reach is 2' do
      expect(described_class.threatens?(attacker: attacker, square: { x: 7, y: 5 }, reach_squares: 2)).to be(true)
    end
  end

  describe '.reach_for' do
    it 'defaults to 1' do
      expect(described_class.reach_for({})).to eq(1)
    end

    it 'reads explicit reach_squares' do
      expect(described_class.reach_for(reach_squares: 2)).to eq(2)
    end
  end
end
