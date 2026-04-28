# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Battlefield::ActionEconomy do
  let(:fresh_economy) do
    {
      'round' => 1,
      'holder' => 'player',
      'standard_available' => true,
      'move_available' => true,
      'swift_available' => true,
      'full_round_claimed' => false
    }
  end

  describe '.build_for_turn_holder' do
    it 'returns a fresh pool seeded with all slots available' do
      pool = described_class.build_for_turn_holder('player', combat_ctx: { 'round' => 3 })
      expect(pool).to include(
        'round' => 3,
        'holder' => 'player',
        'standard_available' => true,
        'move_available' => true,
        'swift_available' => true,
        'full_round_claimed' => false
      )
    end
  end

  describe '.apply_delta!' do
    it 'spends standard, leaving move and swift available' do
      result = described_class.apply_delta!(fresh_economy, 'spend_standard' => true)
      expect(result['standard_available']).to be(false)
      expect(result['move_available']).to be(true)
      expect(result['swift_available']).to be(true)
    end

    it 'spends move' do
      result = described_class.apply_delta!(fresh_economy, 'spend_move' => true)
      expect(result['move_available']).to be(false)
    end

    it 'spends swift' do
      result = described_class.apply_delta!(fresh_economy, 'spend_swift' => true)
      expect(result['swift_available']).to be(false)
    end

    it 'rejects spending an unavailable standard action' do
      spent = described_class.apply_delta!(fresh_economy, 'spend_standard' => true)
      expect do
        described_class.apply_delta!(spent, 'spend_standard' => true)
      end.to raise_error(ArgumentError, /standard action unavailable/)
    end

    it 'rejects spending an unavailable move action' do
      spent = described_class.apply_delta!(fresh_economy, 'spend_move' => true)
      expect do
        described_class.apply_delta!(spent, 'spend_move' => true)
      end.to raise_error(ArgumentError, /move action unavailable/)
    end

    it 'rejects spending an unavailable swift action' do
      spent = described_class.apply_delta!(fresh_economy, 'spend_swift' => true)
      expect do
        described_class.apply_delta!(spent, 'spend_swift' => true)
      end.to raise_error(ArgumentError, /swift action unavailable/)
    end

    context 'full-round actions' do
      it 'consumes both standard and move and marks the round claimed' do
        result = described_class.apply_delta!(fresh_economy, 'spend_full_round' => true)
        expect(result['standard_available']).to be(false)
        expect(result['move_available']).to be(false)
        expect(result['full_round_claimed']).to be(true)
      end

      it 'rejects a second full-round claim in the same turn' do
        once = described_class.apply_delta!(fresh_economy, 'spend_full_round' => true)
        expect do
          described_class.apply_delta!(once, 'spend_full_round' => true)
        end.to raise_error(ArgumentError, /full-round already claimed/)
      end

      it 'rejects full-round when standard or move is already spent' do
        spent_standard = described_class.apply_delta!(fresh_economy, 'spend_standard' => true)
        expect do
          described_class.apply_delta!(spent_standard, 'spend_full_round' => true)
        end.to raise_error(ArgumentError, /full-round requires both standard and move/)
      end
    end

    context 'refunds' do
      it 'refunds a spent standard' do
        spent = described_class.apply_delta!(fresh_economy, 'spend_standard' => true)
        refunded = described_class.apply_delta!(spent, 'refund_standard' => true)
        expect(refunded['standard_available']).to be(true)
      end

      it 'refunds a spent move' do
        spent = described_class.apply_delta!(fresh_economy, 'spend_move' => true)
        refunded = described_class.apply_delta!(spent, 'refund_move' => true)
        expect(refunded['move_available']).to be(true)
      end

      it 'refunds a spent swift' do
        spent = described_class.apply_delta!(fresh_economy, 'spend_swift' => true)
        refunded = described_class.apply_delta!(spent, 'refund_swift' => true)
        expect(refunded['swift_available']).to be(true)
      end
    end

    it 'accepts string-keyed deltas (apply_delta! deep-stringifies)' do
      result = described_class.apply_delta!(fresh_economy, spend_standard: true)
      expect(result['standard_available']).to be(false)
    end

    it 'accepts string "true" as truthy in deltas' do
      result = described_class.apply_delta!(fresh_economy, 'spend_standard' => 'true')
      expect(result['standard_available']).to be(false)
    end

    it 'returns a copy without mutating the input economy' do
      input = fresh_economy.dup
      described_class.apply_delta!(input, 'spend_standard' => true)
      expect(input['standard_available']).to be(true)
    end
  end

  describe '.equip_toggle_cost_delta' do
    it 'is a single move action' do
      expect(described_class.equip_toggle_cost_delta).to eq('spend_move' => true)
    end
  end
end
