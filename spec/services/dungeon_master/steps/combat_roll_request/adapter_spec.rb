# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Steps::CombatRollRequest::Adapter do
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
      derived_stats: { 'ac' => 14, 'touch_ac' => 12, 'flat_footed_ac' => 12 }
    )
  end

  before do
    sheet.update!(derived_stats: { 'ac' => 18, 'melee_attack' => 5, 'ranged_attack' => 3,
                                   'mods' => { 'strength' => 2 } })
    adventure.update!(combat_context: {
                        'active' => true, 'round' => 2, 'current_turn' => 'Player',
                        'participants' => [
                          { 'name' => 'Player', 'type' => 'player' },
                          { 'name' => 'Goblin', 'type' => 'npc', 'creature_sheet_id' => creature.id }
                        ]
                      })
  end

  it 'returns no rolls when needs_roll is false' do
    intent, evals = described_class.call(
      parsed: { 'needs_roll' => false, 'no_roll_reason' => 'positioning only',
                'mechanical_summary' => 'Player drew a weapon.' },
      intention: 'I draw my sword',
      adventure: adventure, sheet: sheet
    )

    expect(intent[:affected_contexts]).to include('combat')
    expect(evals.first[:player_rolls]).to eq([])
    expect(evals.first[:mechanical_summary]).to eq('Player drew a weapon.')
  end

  it 'normalizes a skill_check roll without touching CombatMechanicResolution' do
    intent, evals = described_class.call(
      parsed: {
        'needs_roll' => true,
        'roll' => { 'type' => 'skill_check', 'skill' => 'Acrobatics', 'dc' => 15,
                    'description' => 'Tumble past the goblin', 'rule_slug' => 'acrobatics' },
        'affected_domains' => ['combat'],
        'mechanical_summary' => 'Player attempts an acrobatics tumble.'
      },
      intention: 'I tumble past the goblin',
      adventure: adventure, sheet: sheet
    )

    roll = evals.first[:player_rolls].first
    expect(intent[:affected_contexts]).to eq(['combat'])
    expect(roll[:type]).to eq('skill_check')
    expect(roll[:skill]).to eq('Acrobatics')
    expect(roll[:dc]).to eq(15)
  end

  it 'resolves attack_roll DC via CombatMechanicResolution' do
    intent, evals = described_class.call(
      parsed: {
        'needs_roll' => true,
        'roll' => { 'type' => 'attack_roll', 'attack_option_id' => 'unarmed',
                    'target' => 'Goblin', 'description' => 'Improvised brazier swing.' },
        'affected_domains' => ['combat'],
        'mechanical_summary' => 'Player swings a brazier at the goblin.'
      },
      intention: 'I tip the brazier into the goblin',
      adventure: adventure, sheet: sheet
    )

    roll = evals.first[:player_rolls].first
    expect(intent[:affected_contexts]).to eq(['combat'])
    expect(roll[:type]).to eq('attack_roll')
    expect(roll[:dc]).to eq(14)
    expect(roll[:domain]).to eq('combat')
    expect(roll[:attack_mode]).to eq('melee')
  end

  it 'falls back gracefully when CombatMechanicResolution raises' do
    parsed = {
      'needs_roll' => true,
      'roll' => { 'type' => 'attack_roll', 'attack_option_id' => 'mythical_blade',
                  'target' => 'Goblin', 'description' => 'Bogus attack.' },
      'affected_domains' => ['combat'], 'mechanical_summary' => '...'
    }
    intent, evals = described_class.call(
      parsed: parsed, intention: 'fail',
      adventure: adventure, sheet: sheet
    )

    expect(intent[:affected_contexts]).to eq(['combat'])
    roll = evals.first[:player_rolls].first
    expect(roll[:type]).to eq('attack_roll')
    expect(roll[:error]).to match(/unknown or unavailable attack_option_id/)
  end

  it 'always tags combat as affected even if model omits it' do
    intent, _evals = described_class.call(
      parsed: { 'needs_roll' => false, 'mechanical_summary' => 'shouting' },
      intention: 'I shout',
      adventure: adventure, sheet: sheet
    )

    expect(intent[:affected_contexts]).to include('combat')
  end
end
