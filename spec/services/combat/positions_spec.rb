# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::Positions do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }

  let!(:battlefield) do
    AdventureBattlefield.create!(
      adventure: adventure, status: 'active', topology: 'square', version: 1,
      tokens: {
        'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5, 'type' => 'player' },
        'creature_42' => { 'label' => 'Goblin', 'x' => 7, 'y' => 4, 'type' => 'npc', 'creature_sheet_id' => 42 }
      },
      world: {}, viewport: {}
    )
  end

  before do
    adventure.update!(combat_context: {
                        'active' => true,
                        'battlefield_ref' => { 'id' => battlefield.id, 'version' => battlefield.version, 'topology' => 'square' }
                      })
  end

  describe '.player_position' do
    it 'returns the player token coordinates' do
      pos = described_class.player_position(adventure)
      expect(pos.x).to eq(5)
      expect(pos.y).to eq(5)
      expect(pos.type).to eq('player')
    end
  end

  describe '.position_for_creature_sheet' do
    it 'finds NPCs by creature_sheet_id' do
      pos = described_class.position_for_creature_sheet(adventure, 42)
      expect(pos.label).to eq('Goblin')
      expect([pos.x, pos.y]).to eq([7, 4])
    end
  end

  describe '.occupied?' do
    it 'returns true for the goblin square' do
      expect(described_class.occupied?(adventure, x: 7, y: 4)).to be(true)
    end

    it 'returns false for an empty square' do
      expect(described_class.occupied?(adventure, x: 9, y: 9)).to be(false)
    end

    it 'ignores the player when except_token_id is "player"' do
      expect(described_class.occupied?(adventure, x: 5, y: 5, except_token_id: 'player')).to be(false)
    end
  end

  describe '.speed_squares_for' do
    it 'converts feet to squares' do
      sheet.update!(derived_stats: { 'speed' => 30 })
      expect(described_class.speed_squares_for(sheet)).to eq(6)
    end

    it 'falls back to 6 when speed is missing' do
      sheet.update!(derived_stats: {})
      expect(described_class.speed_squares_for(sheet)).to eq(6)
    end
  end

  describe '.move_player_token!' do
    it 'updates the player x/y, bumps version, and syncs battlefield_ref' do
      described_class.move_player_token!(adventure, x: 8, y: 8)

      battlefield.reload
      expect(battlefield.tokens['player']).to include('x' => 8, 'y' => 8)
      expect(battlefield.version).to eq(2)
      expect(adventure.reload.combat_context.dig('battlefield_ref', 'version')).to eq(2)
    end
  end

  describe 'Position#distance_to (Chebyshev)' do
    it 'is the max of |dx| and |dy|' do
      a = described_class::Position.new(token_id: 'a', label: 'A', x: 0, y: 0)
      b = described_class::Position.new(token_id: 'b', label: 'B', x: 3, y: 4)
      expect(a.distance_to(b)).to eq(4)
    end
  end
end
