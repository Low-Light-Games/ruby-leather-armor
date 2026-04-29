# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Rolls::HashArray do
  describe '.symbolize_strict' do
    it 'symbolizes hash entries' do
      result = described_class.symbolize_strict([{ 'kind' => 'attack', 'name' => 'shortsword' }])
      expect(result).to eq([{ kind: 'attack', name: 'shortsword' }])
    end

    it 'drops string entries instead of crashing on deep_symbolize_keys' do
      result = described_class.symbolize_strict([{ 'kind' => 'attack' }, 'oops a string'])
      expect(result).to eq([{ kind: 'attack' }])
    end

    it 'drops nil + non-hash entries' do
      result = described_class.symbolize_strict([nil, 42, ['nested'], { 'kept' => true }])
      expect(result).to eq([{ kept: true }])
    end

    it 'returns [] for nil input' do
      expect(described_class.symbolize_strict(nil)).to eq([])
    end
  end
end
