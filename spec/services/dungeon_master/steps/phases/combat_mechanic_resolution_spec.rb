# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Steps::Phases::CombatMechanicResolution do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }

  before do
    adventure.update!(combat_context: { 'active' => true, 'participants' => [] })
  end

  describe 'consequences normalization' do
    def call_with(consequences:)
      described_class.call(
        parsed: {
          player_rolls: [], npc_actions: [],
          consequences: consequences,
          mechanical_summary: 'ok'
        },
        domain: 'combat', adventure: adventure, sheet: sheet
      )
    end

    it 'wraps plain string consequences from the AI as { description: ... }' do
      result = call_with(consequences: ['Aldric closes to melee.'])
      expect(result[:consequences]).to eq([{ description: 'Aldric closes to melee.' }])
    end

    it 'symbolizes hash consequences' do
      result = call_with(consequences: [{ 'description' => 'Door slams shut.', 'severity' => 'minor' }])
      expect(result[:consequences]).to eq([{ description: 'Door slams shut.', severity: 'minor' }])
    end

    it 'silently drops unsupported entry types instead of crashing' do
      result = call_with(consequences: [42, nil, ['nested', 'array'], { 'description' => 'kept' }])
      expect(result[:consequences]).to eq([{ description: 'kept' }])
    end
  end
end
