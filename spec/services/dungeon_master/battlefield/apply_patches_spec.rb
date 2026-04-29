# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Battlefield::ApplyPatches do
  let(:user)      { create(:user, :password_auth) }
  let(:story)    { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }
  let!(:battlefield) do
    AdventureBattlefield.create!(
      adventure: adventure, status: 'active', topology: 'square', version: 1,
      tokens: { 'creature_42' => { 'label' => 'Goblin', 'x' => 5, 'y' => 5, 'type' => 'npc' } },
      world: {}, viewport: {}
    )
  end

  before do
    adventure.update!(combat_context: {
                        'active' => true,
                        'battlefield_ref' => { 'id' => battlefield.id, 'version' => battlefield.version, 'topology' => 'square' }
                      })
  end

  it 'accepts the canonical move_token shape (op/id/x/y)' do
    described_class.call(adventure: adventure,
                         patches: [{ 'op' => 'move_token', 'id' => 'creature_42', 'x' => 8, 'y' => 9 }])
    expect(battlefield.reload.tokens.dig('creature_42', 'x')).to eq(8)
    expect(battlefield.reload.tokens.dig('creature_42', 'y')).to eq(9)
  end

  it 'accepts the verbose alias shape (operation/token_id/to_x/to_y)' do
    described_class.call(
      adventure: adventure,
      patches: [{ 'operation' => 'move_token', 'token_id' => 'creature_42', 'to_x' => 12, 'to_y' => 14 }]
    )
    expect(battlefield.reload.tokens.dig('creature_42', 'x')).to eq(12)
    expect(battlefield.reload.tokens.dig('creature_42', 'y')).to eq(14)
  end

  it 'still raises a clear AiError for genuinely unknown ops' do
    expect {
      described_class.call(adventure: adventure, patches: [{ 'op' => 'teleport_token' }])
    }.to raise_error(DungeonMaster::AiError, /battlefield patch: unknown op "teleport_token"/)
  end
end
