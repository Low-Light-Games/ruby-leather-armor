# frozen_string_literal: true

require 'rails_helper'

# Regression: bare `Combat::Positions` inside DungeonMaster::Steps::
# CombatRollRequest resolves to DungeonMaster::Combat first (where
# AttackOptionBuilder lives) and never finds Positions, raising
# NameError: uninitialized constant DungeonMaster::Combat::Positions
# at runtime. This spec exercises build_threats_for_player end-to-end
# against the live Combat::Positions module so any future refactor
# that drops the `::` prefix fails here instead of in the pipeline.
RSpec.describe 'DungeonMaster::Steps::CombatRollRequest threats builder' do
  # Minimal host that mixes the module in so we can call its private
  # methods without spinning up the entire Steps pipeline.
  let(:host_class) do
    Class.new do
      include DungeonMaster::Steps::CombatRollRequest

      def initialize(adventure)
        @adventure = adventure
      end

      def threats
        build_threats_for_player
      end
    end
  end

  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }
  let(:creature) do
    CreatureSheet.create!(
      adventure: adventure,
      name: 'Goblin', creature_type: 'monster', origin: 'ai', attitude: 'hostile',
      level: 1,
      strength: 11, dexterity: 13, constitution: 12,
      intelligence: 10, wisdom: 9, charisma: 6,
      hp: 6, max_hp: 6,
      derived_stats: { 'ac' => 14 }
    )
  end

  let(:host) { host_class.new(adventure) }

  context 'with no battlefield grid' do
    before do
      adventure.update!(combat_context: { 'active' => true, 'round' => 1, 'current_turn' => 'Player' })
    end

    it 'returns [] without raising NameError on Combat::Positions' do
      expect { host.threats }.not_to raise_error
      expect(host.threats).to eq([])
    end
  end

  context 'with a battlefield + adjacent enemy' do
    let!(:battlefield) do
      AdventureBattlefield.create!(
        adventure: adventure, status: 'active', topology: 'square', version: 1,
        tokens: {
          'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5, 'type' => 'player' },
          "creature_#{creature.id}" => { 'label' => 'Goblin', 'x' => 6, 'y' => 5,
                                         'type' => 'npc', 'creature_sheet_id' => creature.id }
        }, world: {}, viewport: {}
      )
    end

    before do
      adventure.update!(combat_context: {
                          'active' => true, 'round' => 1, 'current_turn' => 'Player',
                          'participants' => [
                            { 'name' => 'Player', 'type' => 'player' },
                            { 'name' => 'Goblin', 'type' => 'npc', 'creature_sheet_id' => creature.id }
                          ],
                          'battlefield_ref' => { 'id' => battlefield.id, 'version' => battlefield.version,
                                                 'topology' => 'square' }
                        })
    end

    it 'reports the adjacent goblin as a threat with grid coordinates' do
      threats = host.threats
      expect(threats.length).to eq(1)
      expect(threats.first).to include(name: 'Goblin', x: 6, y: 5, distance_squares: 1)
    end
  end
end
