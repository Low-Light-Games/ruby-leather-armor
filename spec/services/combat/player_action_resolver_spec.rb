# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::PlayerActionResolver do
  let(:user)      { create(:user, :password_auth, combat_dice_strategy: 'server') }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }

  let(:creature) do
    CreatureSheet.create!(
      adventure: adventure,
      name: 'Goblin',
      creature_type: 'monster',
      origin: 'ai',
      attitude: 'hostile',
      level: 1,
      strength: 11, dexterity: 13, constitution: 12,
      intelligence: 10, wisdom: 9, charisma: 6,
      hp: 6, max_hp: 6,
      derived_stats: { 'ac' => 14, 'touch_ac' => 12, 'flat_footed_ac' => 12 }
    )
  end

  let(:player_attack_bonus) { 5 }
  let(:strength_mod)        { 2 }

  before do
    sheet.update!(
      derived_stats: {
        'ac' => 18, 'touch_ac' => 12, 'flat_footed_ac' => 16,
        'melee_attack' => player_attack_bonus, 'ranged_attack' => player_attack_bonus,
        'mods' => { 'strength' => strength_mod }
      }
    )

    adventure.update!(
      combat_context: {
        'active' => true,
        'round' => 1,
        'current_turn' => DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME,
        'participants' => [
          { 'name' => 'Player' },
          { 'name' => 'Goblin', 'creature_sheet_id' => creature.id }
        ],
        'action_economy' => {
          'round' => 1, 'holder' => 'player',
          'standard_available' => true, 'move_available' => true,
          'swift_available' => true, 'full_round_claimed' => false
        }
      }
    )
  end

  let(:base_params) do
    {
      kind: 'attack',
      attack_option_id: 'unarmed',
      target_creature_sheet_id: creature.id
    }
  end

  describe 'guards' do
    it 'rejects when combat is not active' do
      adventure.update!(combat_context: { 'active' => false })
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      }.to raise_error(described_class::Error, /combat is not active/)
    end

    it "rejects when it isn't the player's turn" do
      adventure.update!(combat_context: adventure.combat_context.merge('current_turn' => 'Goblin'))
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      }.to raise_error(described_class::Error, /not the player's turn/)
    end

    it 'rejects unsupported kinds' do
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: base_params.merge(kind: 'cast'))
      }.to raise_error(described_class::Error, /unsupported combat action kind/)
    end

    it 'rejects an unknown attack_option_id' do
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: base_params.merge(attack_option_id: 'mythical_blade'))
      }.to raise_error(described_class::Error, /unknown or unavailable attack_option_id/)
    end

    it 'rejects a missing target' do
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: base_params.merge(target_creature_sheet_id: 999_999))
      }.to raise_error(described_class::Error, /creature not found/)
    end

    it 'rejects a target already at 0 HP' do
      creature.update!(hp: 0)
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      }.to raise_error(described_class::Error, /already down/)
    end
  end

  describe 'server dice strategy' do
    it 'resolves a hit, applies HP delta, decrements standard, and logs an action_event' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(15)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(3)

      result = nil
      expect {
        result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      }.to change { PlayLog.where(event_type: 'combat_action').count }.by(1)

      expect(result[:status]).to eq(:resolved)
      expect(result[:result][:hit]).to be(true)
      expect(result[:result][:attack_total]).to eq(15 + player_attack_bonus)
      expect(result[:result][:damage_total]).to eq(3 + strength_mod)
      expect(creature.reload.hp).to eq(6 - (3 + strength_mod))
      expect(adventure.reload.combat_context.dig('action_economy', 'standard_available')).to be(false)
    end

    it 'resolves a miss without changing HP and still spends standard' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(5)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(99)

      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)

      expect(result[:result][:hit]).to be(false)
      expect(result[:result][:damage_total]).to be_nil
      expect(creature.reload.hp).to eq(6)
      expect(adventure.reload.combat_context.dig('action_economy', 'standard_available')).to be(false)
    end

    it 'natural 20 always hits and is flagged as a crit threat' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(20)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(2)

      sheet.update!(derived_stats: sheet.derived_stats.merge('melee_attack' => -50))

      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)

      expect(result[:result][:hit]).to be(true)
      expect(result[:result][:crit_threat]).to be(true)
    end

    it 'natural 1 always misses' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(1)
      sheet.update!(derived_stats: sheet.derived_stats.merge('melee_attack' => 50))

      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)

      expect(result[:result][:hit]).to be(false)
      expect(result[:result][:natural_one]).to be(true)
    end

    it 'flags target_dropped when HP reaches 0' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(20)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(99)

      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)

      expect(result[:result][:target_dropped]).to be(true)
      expect(creature.reload.hp).to eq(0)
    end

    it 'rejects the attack when standard is already spent' do
      adventure.update!(combat_context: adventure.combat_context.deep_merge(
        'action_economy' => { 'standard_available' => false }
      ))

      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      }.to raise_error(described_class::Error, /unknown or unavailable attack_option_id/)
      # AttackOptionBuilder hides options when the standard slot is gone.
    end
  end

  describe 'end turn' do
    it 'advances the round, resets the action economy, and stays on the player' do
      adventure.update!(combat_context: adventure.combat_context.deep_merge(
        'action_economy' => { 'standard_available' => false, 'move_available' => false }
      ))

      result = nil
      expect {
        result = described_class.call(adventure: adventure, sheet: sheet, user: user,
                                       params: { kind: 'end_turn' })
      }.to change { PlayLog.where(event_type: 'combat_action').count }.by(1)

      expect(result[:status]).to eq(:resolved)
      expect(result[:result][:round_advanced_to]).to eq(2)
      expect(result[:result][:npc_actions_skipped]).to be(true)

      ctx = adventure.reload.combat_context
      expect(ctx['round']).to eq(2)
      expect(ctx['current_turn']).to eq('Player')
      expect(ctx['action_economy']['standard_available']).to be(true)
      expect(ctx['action_economy']['move_available']).to be(true)
      expect(ctx['action_economy']['swift_available']).to be(true)
    end

    it 'rejects when not the player turn' do
      adventure.update!(combat_context: adventure.combat_context.merge('current_turn' => 'Goblin'))
      expect {
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: { kind: 'end_turn' })
      }.to raise_error(described_class::Error, /not the player's turn/)
    end
  end

  describe 'client dice strategy' do
    let(:user) { create(:user, :password_auth, combat_dice_strategy: 'client') }

    it 'returns an awaiting_player_dice payload on first call' do
      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)

      expect(result[:status]).to eq(:awaiting_player_dice)
      expect(result[:request]).to include(
        attack_option_id: 'unarmed',
        target_name: 'Goblin',
        attack_bonus: player_attack_bonus,
        defense_dc: 14,
        damage_ability_bonus: strength_mod
      )
      expect(creature.reload.hp).to eq(6)
      expect(adventure.reload.combat_context.dig('action_economy', 'standard_available')).to be(true)
    end

    it 'resolves with player-supplied naturals on the second call' do
      result = described_class.call(
        adventure: adventure, sheet: sheet, user: user, params: base_params,
        submitted_dice: { attack_natural: 14, damage_natural: 5 }
      )

      expect(result[:status]).to eq(:resolved)
      expect(result[:result][:attack_natural]).to eq(14)
      expect(result[:result][:hit]).to be(true)
      expect(result[:result][:damage_natural]).to eq(5)
      expect(result[:result][:damage_total]).to eq(5 + strength_mod)
      # 6 HP - 7 dmg = -1, clamped to the [0, max_hp] floor.
      expect(creature.reload.hp).to eq(0)
      expect(result[:result][:target_dropped]).to be(true)
    end

    it 'has no effect on end_turn (no dice involved)' do
      result = described_class.call(
        adventure: adventure, sheet: sheet, user: user,
        params: { kind: 'end_turn' }
      )
      expect(result[:status]).to eq(:resolved)
      expect(result[:result][:kind]).to eq('end_turn')
    end

    it 'rejects an out-of-range natural roll' do
      expect {
        described_class.call(
          adventure: adventure, sheet: sheet, user: user, params: base_params,
          submitted_dice: { attack_natural: 25, damage_natural: 3 }
        )
      }.to raise_error(described_class::Error, /invalid attack_natural/)
    end
  end
end
