# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Rolls::Consequences do
  describe '.normalize' do
    it 'symbolizes hash entries' do
      result = described_class.normalize([{ 'description' => 'Door slams shut.' }])
      expect(result).to eq([{ description: 'Door slams shut.' }])
    end

    it 'wraps plain string entries as { description: ... }' do
      result = described_class.normalize(['Aldric closes to melee.'])
      expect(result).to eq([{ description: 'Aldric closes to melee.' }])
    end

    it 'mixes both shapes in one pass' do
      result = described_class.normalize([
                                           'Aldric closes.',
                                           { 'description' => 'Door slams shut.', 'severity' => 'minor' }
                                         ])
      expect(result).to eq([
                             { description: 'Aldric closes.' },
                             { description: 'Door slams shut.', severity: 'minor' }
                           ])
    end

    it 'drops nil + non-hash non-string entries' do
      result = described_class.normalize([nil, 42, ['nested'], 'kept', { 'description' => 'also kept' }])
      expect(result).to eq([{ description: 'kept' }, { description: 'also kept' }])
    end

    it 'returns [] for nil input' do
      expect(described_class.normalize(nil)).to eq([])
    end
  end
end
