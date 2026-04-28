# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CombatActions', type: :request do
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

  before do
    sign_in(user)
    sheet.update!(derived_stats: {
                    'ac' => 18, 'touch_ac' => 12, 'flat_footed_ac' => 16,
                    'melee_attack' => 5, 'ranged_attack' => 5,
                    'mods' => { 'strength' => 2 }
                  })
    adventure.update!(combat_context: {
                        'active' => true, 'round' => 1, 'current_turn' => 'Player',
                        'participants' => [
                          { 'name' => 'Player' },
                          { 'name' => 'Goblin', 'creature_sheet_id' => creature.id }
                        ],
                        'action_economy' => {
                          'round' => 1, 'holder' => 'player',
                          'standard_available' => true, 'move_available' => true,
                          'swift_available' => true, 'full_round_claimed' => false
                        }
                      })
  end

  describe 'GET /adventures/:id/combat_action/options' do
    it 'returns attack options, hostile targets, action economy, and dice strategy' do
      get "/adventures/#{adventure.id}/combat_action/options",
          headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['dice_strategy']).to eq('server')
      expect(body['action_economy']['standard_available']).to be(true)
      expect(body['attack_options']).to be_an(Array)
      expect(body['attack_options'].map { |o| o['id'] }).to include('unarmed')
      expect(body['targets']).to contain_exactly(
        a_hash_including('creature_sheet_id' => creature.id, 'name' => 'Goblin')
      )
      expect(body).to include('player_speed_squares')
    end
  end

  describe 'POST /adventures/:id/combat_action move' do
    let!(:battlefield) do
      AdventureBattlefield.create!(
        adventure: adventure, status: 'active', topology: 'square', version: 1,
        tokens: {
          'player' => { 'label' => 'Player', 'x' => 5, 'y' => 5, 'type' => 'player' }
        },
        world: {}, viewport: {}
      )
    end

    before do
      adventure.update!(combat_context: adventure.combat_context.merge(
                          'battlefield_ref' => { 'id' => battlefield.id, 'version' => battlefield.version, 'topology' => 'square' }
                        ))
      sheet.update!(derived_stats: sheet.derived_stats.merge('speed' => 30))
    end

    it 'moves the player to the target square' do
      post "/adventures/#{adventure.id}/combat_action",
           params: { kind: 'move', x: 8, y: 8 }, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data['result']['kind']).to eq('move')
      expect(data['result']['to']).to eq('x' => 8, 'y' => 8)
      expect(data['combat_context']['action_economy']['move_available']).to be(false)
    end
  end

  describe 'POST /adventures/:id/combat_action' do
    let(:body) do
      {
        kind: 'attack', attack_option_id: 'unarmed',
        target_creature_sheet_id: creature.id
      }
    end

    it 'resolves a server-rolled attack and returns the updated combat context' do
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(15)
      allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_damage_expression).and_return(3)

      post "/adventures/#{adventure.id}/combat_action", params: body, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data['status']).to eq('resolved')
      expect(data['result']['hit']).to be(true)
      expect(data['result']['damage_total']).to eq(5)
      expect(data['combat_context']['action_economy']['standard_available']).to be(false)
    end

    it 'returns awaiting_player_dice when the user prefers client rolls' do
      user.update!(combat_dice_strategy: 'client')
      post "/adventures/#{adventure.id}/combat_action", params: body, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data['status']).to eq('awaiting_player_dice')
      expect(data['request']['attack_bonus']).to eq(5)
      expect(data['request']['defense_dc']).to eq(14)
    end

    it 'finalizes a client-rolled attack on the second call with submitted_dice' do
      user.update!(combat_dice_strategy: 'client')
      post "/adventures/#{adventure.id}/combat_action",
           params: body.merge(submitted_dice: { attack_natural: 18, damage_natural: 4 }), as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data['status']).to eq('resolved')
      expect(data['result']['attack_natural']).to eq(18)
      expect(data['result']['damage_natural']).to eq(4)
    end

    it 'rejects with 422 and a code when the resolver raises' do
      adventure.update!(combat_context: adventure.combat_context.merge('current_turn' => 'Goblin'))
      post "/adventures/#{adventure.id}/combat_action", params: body, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      data = JSON.parse(response.body)
      expect(data['code']).to eq('not_player_turn')
    end

    it 'forbids users who do not own the adventure' do
      other = create(:user, :password_auth)
      sign_in(other)
      post "/adventures/#{adventure.id}/combat_action", params: body, as: :json

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end

  describe 'PATCH /user_preferences' do
    it 'flips the combat dice strategy' do
      patch '/user_preferences',
            params: { combat_dice_strategy: 'client' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['combat_dice_strategy']).to eq('client')
      expect(user.reload.combat_dice_strategy).to eq('client')
    end

    it 'rejects unknown strategies' do
      patch '/user_preferences',
            params: { combat_dice_strategy: 'cosmic' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
