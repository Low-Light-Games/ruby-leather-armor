# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Battlefield::ActionEconomy::Snapshot do
  describe '.from_combat_context + slot predicates' do
    it 'reports standard available when the slot is true and full-round not claimed' do
      snap = described_class.from_combat_context(
        'action_economy' => { 'standard_available' => true, 'move_available' => true,
                              'swift_available' => true, 'full_round_claimed' => false }
      )
      expect(snap.standard_available?).to be(true)
      expect(snap.move_available?).to be(true)
      expect(snap.swift_available?).to be(true)
      expect(snap.full_round_claimed?).to be(false)
    end

    it 'reports standard NOT available when full_round was claimed even if standard is still flagged' do
      snap = described_class.from_combat_context(
        'action_economy' => { 'standard_available' => true, 'full_round_claimed' => true }
      )
      expect(snap.standard_available?).to be(false)
    end

    it 'tolerates string boolean values from the JSONB column' do
      snap = described_class.from_combat_context(
        'action_economy' => { 'standard_available' => 'true', 'move_available' => 'false' }
      )
      expect(snap.standard_available?).to be(true)
      expect(snap.move_available?).to be(false)
    end

    it 'returns an empty snapshot for nil / non-hash combat_context' do
      expect(described_class.from_combat_context(nil)).to be_empty
      expect(described_class.from_combat_context('not a hash')).to be_empty
    end
  end
end
