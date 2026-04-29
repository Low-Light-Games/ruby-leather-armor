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
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      end.to raise_error(described_class::Error, /combat is not active/)
    end

    it "rejects when it isn't the player's turn" do
      adventure.update!(combat_context: adventure.combat_context.merge('current_turn' => 'Goblin'))
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      end.to raise_error(described_class::Error, /not the player's turn/)
    end

    it 'rejects unsupported kinds' do
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: base_params.merge(kind: 'cast'))
      end.to raise_error(described_class::Error, /unsupported combat action kind/)
    end

    it 'rejects an unknown attack_option_id' do
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: base_params.merge(attack_option_id: 'mythical_blade'))
      end.to raise_error(described_class::Error, /unknown or unavailable attack_option_id/)
    end

    it 'rejects a missing target' do
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: base_params.merge(target_creature_sheet_id: 999_999))
      end.to raise_error(described_class::Error, /creature not found/)
    end

    it 'rejects a target already at 0 HP' do
      creature.update!(hp: 0)
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      end.to raise_error(described_class::Error, /already down/)
    end
  end

  describe 'server dice strategy' do
    it 'resolves a hit, applies HP delta, decrements standard, and logs an action_event' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(15)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(3)

      result = nil
      expect do
        result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      end.to change { PlayLog.where(event_type: 'combat_action').count }.by(1)

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

    it 'ends combat when the last hostile NPC drops' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(20)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(99)

      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)

      expect(result[:result][:target_dropped]).to be(true)
      expect(result[:result][:combat_ended]).to be(true)
      expect(result[:result][:combat_end_reason]).to eq('all_npcs_defeated')
      ctx = adventure.reload.combat_context
      expect(ctx['active']).to be(false)
      expect(ctx['current_turn']).to be_nil
      expect(ctx['action_economy']).to be_nil
      expect(ctx['combat_end_reason']).to eq('all_npcs_defeated')
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

      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      end.to raise_error(described_class::Error, /unknown or unavailable attack_option_id/)
      # AttackOptionBuilder hides options when the standard slot is gone.
    end
  end

  describe 'situational modifiers' do
    let!(:battlefield) do
      AdventureBattlefield.create!(
        adventure: adventure, status: 'active', topology: 'square', version: 1,
        tokens: {
          'player' => { 'label' => 'Player', 'x' => 4, 'y' => 5, 'type' => 'player' },
          "creature_#{creature.id}" => { 'label' => 'Goblin', 'x' => 5, 'y' => 5, 'type' => 'npc',
                                         'creature_sheet_id' => creature.id },
          'creature_99' => { 'label' => 'Fighter', 'x' => 6, 'y' => 5, 'type' => 'npc', 'creature_sheet_id' => 99 }
        },
        world: {}, viewport: {}
      )
    end

    before do
      adventure.update!(combat_context: adventure.combat_context.merge(
        'battlefield_ref' => { 'id' => battlefield.id, 'version' => battlefield.version,
                               'topology' => 'square' }
      ))
    end

    it 'adds the flanking bonus when an ally sits opposite' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(10)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(1)

      result = described_class.call(adventure: adventure, sheet: sheet, user: user, params: base_params)
      expect(result[:result][:flanking]).to be(true)
      expect(result[:result][:flanking_bonus]).to eq(2)
      expect(result[:result][:attack_bonus]).to eq(player_attack_bonus + 2)
      expect(result[:result][:message]).to include('+2 flanking')
    end
  end

  describe 'movement' do
    let!(:battlefield) do
      AdventureBattlefield.create!(
        adventure: adventure, status: 'active', topology: 'square', version: 1,
        tokens: {
          'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5, 'type' => 'player' },
          "creature_#{creature.id}" => { 'label' => 'Goblin', 'x' => 7, 'y' => 4, 'type' => 'npc',
                                         'creature_sheet_id' => creature.id }
        },
        world: {}, viewport: {}
      )
    end

    before do
      adventure.update!(combat_context: adventure.combat_context.merge(
        'battlefield_ref' => { 'id' => battlefield.id, 'version' => battlefield.version,
                               'topology' => 'square' }
      ))
      sheet.update!(derived_stats: sheet.derived_stats.merge('speed' => 30))
    end

    it 'moves the player and spends the move action' do
      result = described_class.call(
        adventure: adventure, sheet: sheet, user: user,
        params: { kind: 'move', x: 9, y: 8 }
      )
      expect(result[:status]).to eq(:resolved)
      expect(result[:result][:to]).to eq(x: 9, y: 8)
      expect(result[:result][:movement_mode]).to eq('move')
      expect(adventure.reload.combat_context.dig('action_economy', 'move_available')).to be(false)
      expect(battlefield.reload.tokens.dig('player', 'x')).to eq(9)
    end

    it 'tags a 1-square move as a 5-foot step' do
      result = described_class.call(
        adventure: adventure, sheet: sheet, user: user,
        params: { kind: 'move', x: 5, y: 6 }
      )
      expect(result[:result][:movement_mode]).to eq('5-foot step')
    end

    it 'still tags a 1-square move as a 5-foot step after standard is spent' do
      # PF1e: a 5-foot step is legal as long as the move slot is unspent
      # and no full-round was claimed. Spending the standard action on
      # an attack does NOT block it.
      adventure.update!(combat_context: adventure.combat_context.deep_merge(
        'action_economy' => { 'standard_available' => false }
      ))

      result = described_class.call(
        adventure: adventure, sheet: sheet, user: user,
        params: { kind: 'move', x: 5, y: 6 }
      )
      expect(result[:result][:movement_mode]).to eq('5-foot step')
      expect(result[:result][:attacks_of_opportunity]).to eq([])
    end

    it 'rejects moves beyond speed' do
      expect do
        described_class.call(
          adventure: adventure, sheet: sheet, user: user,
          params: { kind: 'move', x: 20, y: 20 }
        )
      end.to raise_error(described_class::Error, /squares away/)
    end

    it 'rejects moves onto another combatant' do
      expect do
        described_class.call(
          adventure: adventure, sheet: sheet, user: user,
          params: { kind: 'move', x: 7, y: 4 }
        )
      end.to raise_error(described_class::Error, /occupied/)
    end

    it 'rejects no-op moves to the current square' do
      expect do
        described_class.call(
          adventure: adventure, sheet: sheet, user: user,
          params: { kind: 'move', x: 5, y: 5 }
        )
      end.to raise_error(described_class::Error, /already on that square/)
    end

    it 'provokes AoO from adjacent enemies and applies damage to the player' do
      creature.update!(
        equipped_weapons: [{ 'name' => 'shortsword', 'damage_dice' => '1d6', 'damage_type' => 'piercing' }],
        derived_stats: creature.derived_stats.merge('melee_attack' => 5, 'mods' => { 'strength' => 1 })
      )
      sheet.update!(hp: 12, derived_stats: sheet.derived_stats.merge('ac' => 10))
      AdventureBattlefield.find(battlefield.id).update!(tokens: {
                                                          'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5,
                                                                        'type' => 'player' },
                                                          "creature_#{creature.id}" => {
                                                            'label' => 'Goblin', 'x' => 6, 'y' => 5,
                                                            'type' => 'npc',
                                                            'creature_sheet_id' => creature.id
                                                          }
                                                        })

      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(15)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(4)

      result = described_class.call(adventure: adventure, sheet: sheet, user: user,
                                    params: { kind: 'move', x: 5, y: 9 })

      expect(result[:result][:attacks_of_opportunity].length).to eq(1)
      aoo = result[:result][:attacks_of_opportunity].first
      expect(aoo['hit']).to be(true)
      expect(aoo['damage_total']).to eq(5)
      expect(sheet.reload.hp).to eq(12 - 5)
    end

    it 'does not provoke on a 5-foot step' do
      creature.update!(derived_stats: creature.derived_stats.merge('melee_attack' => 5))
      AdventureBattlefield.find(battlefield.id).update!(tokens: {
                                                          'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5,
                                                                        'type' => 'player' },
                                                          "creature_#{creature.id}" => {
                                                            'label' => 'Goblin', 'x' => 6, 'y' => 5,
                                                            'type' => 'npc',
                                                            'creature_sheet_id' => creature.id
                                                          }
                                                        })

      result = described_class.call(adventure: adventure, sheet: sheet, user: user,
                                    params: { kind: 'move', x: 5, y: 6 })
      expect(result[:result][:movement_mode]).to eq('5-foot step')
      expect(result[:result][:attacks_of_opportunity]).to eq([])
    end

    it 'withdraws as a full-round action and skips departure-square AoO' do
      creature.update!(
        equipped_weapons: [{ 'name' => 'shortsword', 'damage_dice' => '1d6', 'damage_type' => 'piercing' }],
        derived_stats: creature.derived_stats.merge('melee_attack' => 5, 'mods' => { 'strength' => 1 })
      )
      sheet.update!(hp: 12, derived_stats: sheet.derived_stats.merge('ac' => 10))
      AdventureBattlefield.find(battlefield.id).update!(tokens: {
                                                          'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5,
                                                                        'type' => 'player' },
                                                          "creature_#{creature.id}" => {
                                                            'label' => 'Goblin', 'x' => 6, 'y' => 5,
                                                            'type' => 'npc',
                                                            'creature_sheet_id' => creature.id
                                                          }
                                                        })

      result = described_class.call(adventure: adventure, sheet: sheet, user: user,
                                    params: { kind: 'move', x: 5, y: 9, withdraw: true })

      expect(result[:result][:movement_mode]).to eq('withdraw')
      expect(result[:result][:attacks_of_opportunity]).to eq([])
      expect(sheet.reload.hp).to eq(12)
      econ = adventure.reload.combat_context['action_economy']
      expect(econ['standard_available']).to be(false)
      expect(econ['move_available']).to be(false)
      expect(econ['full_round_claimed']).to be(true)
    end

    it 'rejects withdraw when standard is already spent' do
      adventure.update!(combat_context: adventure.combat_context.deep_merge(
        'action_economy' => { 'standard_available' => false }
      ))
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: { kind: 'move', x: 6, y: 6, withdraw: true })
      end.to raise_error(described_class::Error, /withdraw requires both standard and move/)
    end

    it 'rejects when no move action remains' do
      adventure.update!(combat_context: adventure.combat_context.deep_merge(
        'action_economy' => { 'move_available' => false }
      ))
      expect do
        described_class.call(
          adventure: adventure, sheet: sheet, user: user,
          params: { kind: 'move', x: 6, y: 6 }
        )
      end.to raise_error(described_class::Error, /no move action available/)
    end
  end

  describe 'end turn' do
    context 'NPC initiative order' do
      let(:goblin_a) do
        CreatureSheet.create!(
          adventure: adventure, name: 'Goblin Skirmisher', creature_type: 'monster',
          origin: 'ai', attitude: 'hostile', level: 1,
          strength: 11, dexterity: 13, constitution: 12, intelligence: 10, wisdom: 9, charisma: 6,
          hp: 6, max_hp: 6, derived_stats: { 'ac' => 14 }
        )
      end
      let(:goblin_b) do
        CreatureSheet.create!(
          adventure: adventure, name: 'Goblin Boss', creature_type: 'monster',
          origin: 'ai', attitude: 'hostile', level: 1,
          strength: 11, dexterity: 13, constitution: 12, intelligence: 10, wisdom: 9, charisma: 6,
          hp: 6, max_hp: 6, derived_stats: { 'ac' => 14 }
        )
      end

      it 'runs NPCs in turn_order, not by creature_sheet id' do
        # Lower id (goblin_a) goes SECOND in initiative; higher id (goblin_b) goes FIRST.
        adventure.update!(combat_context: adventure.combat_context.merge(
          'turn_order' => ['Goblin Boss', 'Player', 'Goblin Skirmisher'],
          'participants' => [
            { 'name' => 'Goblin Skirmisher', 'type' => 'npc', 'creature_sheet_id' => goblin_a.id },
            { 'name' => 'Player', 'type' => 'player' },
            { 'name' => 'Goblin Boss', 'type' => 'npc', 'creature_sheet_id' => goblin_b.id }
          ]
        ))

        invocations = []
        allow(Combat::NpcTurn).to receive(:call) do |creature:, **_kwargs|
          invocations << creature.id
          []
        end

        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: { kind: 'end_turn' })

        expect(invocations).to eq([goblin_b.id, goblin_a.id])
      end
    end

    it 'advances the round, resets the action economy, and stays on the player' do
      adventure.update!(combat_context: adventure.combat_context.deep_merge(
        'action_economy' => { 'standard_available' => false, 'move_available' => false }
      ))

      result = nil
      expect do
        result = described_class.call(adventure: adventure, sheet: sheet, user: user,
                                      params: { kind: 'end_turn' })
      end.to change { PlayLog.where(event_type: 'combat_action').count }.by(1)

      expect(result[:status]).to eq(:resolved)
      expect(result[:result][:round_advanced_to]).to eq(2)
      expect(result[:result][:npc_events]).to be_an(Array)

      ctx = adventure.reload.combat_context
      expect(ctx['round']).to eq(2)
      expect(ctx['current_turn']).to eq('Player')
      expect(ctx['action_economy']['standard_available']).to be(true)
      expect(ctx['action_economy']['move_available']).to be(true)
      expect(ctx['action_economy']['swift_available']).to be(true)
    end

    it 'rejects when not the player turn' do
      adventure.update!(combat_context: adventure.combat_context.merge('current_turn' => 'Goblin'))
      expect do
        described_class.call(adventure: adventure, sheet: sheet, user: user,
                             params: { kind: 'end_turn' })
      end.to raise_error(described_class::Error, /not the player's turn/)
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
      expect do
        described_class.call(
          adventure: adventure, sheet: sheet, user: user, params: base_params,
          submitted_dice: { attack_natural: 25, damage_natural: 3 }
        )
      end.to raise_error(described_class::Error, /invalid attack_natural/)
    end
  end
end
