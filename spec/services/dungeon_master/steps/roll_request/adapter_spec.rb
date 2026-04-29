# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Steps::RollRequest::Adapter do
  describe '.call' do
    let(:intention) { 'I climb the wall' }

    it 'produces an empty evaluations array when the intent affects nothing' do
      parsed = {
        'needs_roll' => false,
        'no_roll_reason' => 'no in-world effect',
        'affected_domains' => [],
        'mechanical_summary' => 'no-op'
      }

      intent, evaluations = described_class.call(parsed: parsed, intention: intention)

      expect(evaluations).to eq([])
      expect(intent).to include(
        intention: intention,
        affected_contexts: [],
        expand_scene: false,
        transition: nil,
        macro_significant: false,
        combat_ending: false
      )
      expect(intent[:domain_results]).to eq({})
    end

    it 'wraps a needs_roll=true result into one evaluation entry on the primary domain' do
      parsed = {
        'needs_roll' => true,
        'roll' => {
          'type' => 'skill_check',
          'skill' => 'Climb',
          'dc' => 15,
          'description' => 'Climb the wet stone wall',
          'take_10_eligible' => true,
          'take_20_eligible' => false,
          'rule_slug' => 'climbing'
        },
        'affected_domains' => ['exploration'],
        'consequences' => ['wall examined'],
        'mechanical_summary' => 'Climb DC 15.'
      }

      intent, evaluations = described_class.call(parsed: parsed, intention: intention)

      expect(intent[:affected_contexts]).to eq(['exploration'])
      expect(evaluations.length).to eq(1)
      expect(evaluations.first).to include(
        domain: 'exploration',
        consequences: [{ description: 'wall examined' }],
        mechanical_summary: 'Climb DC 15.'
      )

      roll = evaluations.first[:player_rolls].first
      expect(roll).to include(
        type: 'skill_check',
        skill: 'Climb',
        dc: 15,
        domain: 'exploration',
        take_10_eligible: true,
        take_20_eligible: false,
        rule_slug: 'climbing'
      )
    end

    it 'puts the roll only on the primary domain when multiple are affected' do
      parsed = {
        'needs_roll' => true,
        'roll' => { 'type' => 'skill_check', 'skill' => 'Diplomacy', 'dc' => 12 },
        'affected_domains' => %w[traversal social],
        'mechanical_summary' => 'Diplomacy DC 12 to convince the guard.'
      }

      _intent, evaluations = described_class.call(parsed: parsed, intention: 'I bribe the guard so I can pass')

      expect(evaluations.map { |e| e[:domain] }).to eq(%w[social traversal]) # social wins by DOMAIN_PRIORITY
      expect(evaluations.first[:player_rolls].length).to eq(1)
      expect(evaluations.last[:player_rolls]).to eq([])
      expect(evaluations.last[:mechanical_summary]).to eq('(no mechanical involvement in this domain)')
    end

    it 'carries combat_started transition + combatants into intent.domain_results.combat' do
      parsed = {
        'needs_roll' => false,
        'no_roll_reason' => 'initiation only',
        'affected_domains' => ['combat'],
        'transition' => 'combat_started',
        'combatants' => [{ 'goblin' => 3 }, 'goblin chieftain'],
        'mechanical_summary' => 'Combat begins.'
      }

      intent, _evals = described_class.call(parsed: parsed, intention: 'attack the goblin camp')

      expect(intent[:transition]).to eq('combat_started')
      combat = intent[:domain_results]['combat']
      expect(combat[:transition]).to eq('combat_started')
      expect(combat[:combatants]).to eq(['goblin', 'goblin', 'goblin', 'goblin chieftain'])
    end

    it 'ignores expand_scene when social is not in affected_domains' do
      parsed = {
        'needs_roll' => false,
        'no_roll_reason' => 'noop',
        'affected_domains' => ['traversal'],
        'expand_scene' => true,
        'mechanical_summary' => 'ok'
      }

      intent, _evals = described_class.call(parsed: parsed, intention: 'x')

      expect(intent[:expand_scene]).to eq(false)
    end

    it 'honors expand_scene when social is affected' do
      parsed = {
        'needs_roll' => false,
        'no_roll_reason' => 'scene only',
        'affected_domains' => ['social'],
        'expand_scene' => true,
        'mechanical_summary' => 'Approach the merchant.'
      }

      intent, _evals = described_class.call(parsed: parsed, intention: 'I approach the merchant')

      expect(intent[:expand_scene]).to eq(true)
      expect(intent[:domain_results]['social'][:expand_scene]).to eq(true)
    end

    it 'passes through traversal destination' do
      parsed = {
        'needs_roll' => false,
        'no_roll_reason' => 'walking',
        'affected_domains' => ['traversal'],
        'destination' => 'Thornfield',
        'mechanical_summary' => 'Travel toward Thornfield.'
      }

      intent, _evals = described_class.call(parsed: parsed, intention: 'head to Thornfield')

      expect(intent[:destination]).to eq('Thornfield')
      expect(intent[:domain_results]['traversal'][:destination]).to eq('Thornfield')
    end
  end
end
