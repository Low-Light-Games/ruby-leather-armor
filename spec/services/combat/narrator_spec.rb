# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::Narrator do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }
  let(:config)    { DmConfig.instance }
  let(:ai)        { instance_double(DungeonMaster::AiClient) }

  let(:npc_events) do
    [
      { kind: 'npc_attack', creature_id: 1, creature_name: 'Goblin',
        attack_label: 'shortsword',
        outcome: { 'hit' => true, 'damage_total' => 4, 'damage_type' => 'piercing',
                   'target_dropped' => false } },
      { kind: 'npc_move', creature_id: 2, creature_name: 'Orc',
        from: { x: 8, y: 5 }, to: { x: 6, y: 5 } }
    ]
  end

  it 'returns nil when there are no NPC events to narrate' do
    expect(described_class.call(adventure: adventure, sheet: sheet, ai: ai, config: config,
                                round: 1, npc_events: [])).to be_nil
  end

  it 'asks the AI for narration with the round log baked into the prompt' do
    captured = nil
    allow(ai).to receive(:chat) do |**kwargs|
      captured = kwargs[:system_prompt]
      ' Steel rings on shield. The goblin presses; the orc closes. '
    end

    out = described_class.call(adventure: adventure, sheet: sheet, ai: ai, config: config,
                               round: 3, npc_events: npc_events)

    expect(out).to eq('Steel rings on shield. The goblin presses; the orc closes.')
    expect(captured).to include('Round 3')
    expect(captured).to include('Goblin')
    expect(captured).to include('Orc')
    expect(captured).to include('hit you')
  end

  it 'returns nil and logs when the AI raises' do
    log = double('Logging')
    allow(log).to receive(:play_log!)
    allow(ai).to receive(:chat).and_raise(StandardError, 'boom')

    expect(described_class.call(adventure: adventure, sheet: sheet, ai: ai, config: config,
                                round: 1, npc_events: npc_events, log: log)).to be_nil
    expect(log).to have_received(:play_log!).with('combat_narrator_failure', anything, anything)
  end
end
