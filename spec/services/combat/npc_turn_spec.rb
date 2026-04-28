# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::NpcTurn do
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
      derived_stats: { 'ac' => 14, 'melee_attack' => 4, 'speed' => 30, 'mods' => { 'strength' => 0 } },
      equipped_weapons: [{ 'name' => 'shortsword', 'damage_dice' => '1d6', 'damage_type' => 'piercing' }],
      behavior_policy: { 'preferred_attacks' => [{ 'name' => 'shortsword', 'max_range_squares' => 1 }] }
    )
  end

  before do
    sheet.update!(hp: 12, max_hp: 12,
                  derived_stats: { 'ac' => 10, 'melee_attack' => 5, 'mods' => { 'strength' => 2 } })
  end

  def setup_grid(player_xy:, goblin_xy:)
    AdventureBattlefield.create!(
      adventure: adventure, status: 'active', topology: 'square', version: 1,
      tokens: {
        'player' => { 'label' => 'Player', 'x' => player_xy[0], 'y' => player_xy[1], 'type' => 'player' },
        "creature_#{creature.id}" => { 'label' => 'Goblin', 'x' => goblin_xy[0], 'y' => goblin_xy[1],
                                       'type' => 'npc', 'creature_sheet_id' => creature.id }
      }, world: {}, viewport: {}
    ).tap do |bf|
      adventure.update!(combat_context: {
                          'active' => true, 'round' => 1, 'current_turn' => 'Player',
                          'turn_order' => ['Player', 'Goblin'],
                          'participants' => [
                            { 'name' => 'Player', 'type' => 'player' },
                            { 'name' => 'Goblin', 'type' => 'npc', 'creature_sheet_id' => creature.id }
                          ],
                          'battlefield_ref' => { 'id' => bf.id, 'version' => bf.version, 'topology' => 'square' }
                        })
    end
  end

  it 'attacks the player when adjacent' do
    setup_grid(player_xy: [5, 5], goblin_xy: [6, 5])
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(15)
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(3)

    events = described_class.call(creature: creature, adventure: adventure, target_sheet: sheet)

    expect(events.length).to eq(1)
    expect(events.first[:kind]).to eq('npc_attack')
    expect(events.first[:outcome]['hit']).to be(true)
    expect(sheet.reload.hp).to eq(12 - 3)
  end

  it 'approaches and then attacks when out of reach' do
    setup_grid(player_xy: [5, 5], goblin_xy: [10, 5])
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(15)
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(2)

    events = described_class.call(creature: creature, adventure: adventure, target_sheet: sheet)

    expect(events.map { |e| e[:kind] }).to eq(['npc_move', 'npc_attack'])
    new_pos = Combat::Positions.position_for_creature_sheet(adventure, creature.id)
    expect(new_pos.distance_to(Combat::Positions.player_position(adventure))).to eq(1)
  end

  it 'flees when below the morale threshold' do
    creature.update!(hp: 1,
                     behavior_policy: creature.behavior_policy.merge('morale' => { 'flee_at_hp_pct' => 0.5 }))
    setup_grid(player_xy: [5, 5], goblin_xy: [6, 5])

    events = described_class.call(creature: creature, adventure: adventure, target_sheet: sheet)

    expect(events.first[:kind]).to eq('npc_flee')
    new_pos = Combat::Positions.position_for_creature_sheet(adventure, creature.id)
    expect(new_pos.distance_to(Combat::Positions.player_position(adventure))).to be > 1
  end

  it 'skips when the creature is already down' do
    creature.update!(hp: 0)
    setup_grid(player_xy: [5, 5], goblin_xy: [6, 5])

    events = described_class.call(creature: creature, adventure: adventure, target_sheet: sheet)
    expect(events.first[:kind]).to eq('npc_skip')
  end

  it 'uses the policy-named weapon (longbow) and the ranged attack bonus' do
    # Multi-weapon goblin: a longbow listed FIRST and a shortsword listed
    # second. Without the attack_pref → weapon plumbing, NpcAttackResolver
    # would pick the longbow regardless and use the melee bonus, breaking
    # the policy intent.
    creature.update!(
      equipped_weapons: [
        { 'name' => 'longbow', 'damage_dice' => '1d8', 'damage_type' => 'piercing', 'weapon_type' => 'ranged' },
        { 'name' => 'shortsword', 'damage_dice' => '1d6', 'damage_type' => 'piercing' }
      ],
      derived_stats: creature.derived_stats.merge('melee_attack' => 4, 'ranged_attack' => 7),
      behavior_policy: { 'preferred_attacks' => [
        { 'name' => 'longbow', 'min_range_squares' => 2 },
        { 'name' => 'shortsword', 'max_range_squares' => 1 }
      ] }
    )
    setup_grid(player_xy: [5, 5], goblin_xy: [10, 5])
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(10)
    allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(3)

    actual_outcome = Combat::NpcAttackResolver.method(:call)
    captured = nil
    allow(Combat::NpcAttackResolver).to receive(:call) do |**kwargs|
      captured = kwargs
      actual_outcome.call(**kwargs)
    end

    events = described_class.call(creature: creature, adventure: adventure, target_sheet: sheet)
    attack = events.find { |e| e[:kind] == 'npc_attack' }

    expect(captured[:attack_pref]&.name).to eq('longbow')
    # natural 10 + ranged_attack 7 = 17; melee_attack would have been 14.
    expect(attack[:outcome]['total']).to eq(17)
  end

  it 'skips when no preferred attack matches and approach is disabled' do
    creature.update!(behavior_policy: { 'preferred_attacks' => [{ 'name' => 'shortsword', 'max_range_squares' => 1 }],
                                        'approach_when_out_of_reach' => false })
    setup_grid(player_xy: [5, 5], goblin_xy: [10, 5])

    events = described_class.call(creature: creature, adventure: adventure, target_sheet: sheet)
    expect(events.first[:kind]).to eq('npc_skip')
  end
end
