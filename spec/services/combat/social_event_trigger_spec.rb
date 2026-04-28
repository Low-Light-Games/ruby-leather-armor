# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::SocialEventTrigger do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:attack_event) do
    {
      kind: 'attack', attack_label: 'Longsword',
      target_name: 'Goblin', message: 'Longsword vs Goblin: 14 vs AC 12 — hits.'
    }
  end

  describe '.evaluate' do
    it 'returns nil for non-attack actions (move, end_turn)' do
      expect(described_class.evaluate(adventure, kind: 'move')).to be_nil
      expect(described_class.evaluate(adventure, kind: 'end_turn')).to be_nil
    end

    it 'returns nil when no NPCs are present in the social context' do
      adventure.update!(social_context: { 'npcs_present' => [] })
      expect(described_class.evaluate(adventure, attack_event)).to be_nil
    end

    it 'returns nil when only hostile NPCs are present' do
      adventure.update!(social_context: {
                          'npcs_present' => [{ 'name' => 'Bandit Captain', 'attitude' => 'hostile' }]
                        })
      expect(described_class.evaluate(adventure, attack_event)).to be_nil
    end

    it 'fires when a non-hostile NPC is in the scene' do
      adventure.update!(social_context: {
                          'npcs_present' => [
                            { 'name' => 'Tavernkeeper', 'attitude' => 'friendly' },
                            { 'name' => 'Hostile Bandit', 'attitude' => 'hostile' }
                          ]
                        })

      payload = described_class.evaluate(adventure, attack_event)

      expect(payload['kind']).to eq('social_event_triggered')
      expect(payload['action_kind']).to eq('attack')
      expect(payload['witnesses'].map { |w| w['name'] }).to eq(['Tavernkeeper'])
    end
  end

  describe '.maybe_log!' do
    it 'writes a play_log row when the trigger fires' do
      adventure.update!(social_context: {
                          'npcs_present' => [{ 'name' => 'Tavernkeeper', 'attitude' => 'friendly' }]
                        })

      expect do
        described_class.maybe_log!(adventure, attack_event)
      end.to change { PlayLog.where(event_type: 'social_event_triggered').count }.by(1)
    end

    it 'is a no-op when the trigger does not fire' do
      adventure.update!(social_context: { 'npcs_present' => [] })

      expect do
        described_class.maybe_log!(adventure, attack_event)
      end.not_to change(PlayLog, :count)
    end
  end
end
