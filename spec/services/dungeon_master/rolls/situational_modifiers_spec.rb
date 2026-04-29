# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Rolls::SituationalModifiers do
  describe '.normalize' do
    it 'symbolizes hash entries' do
      result = described_class.normalize([{ 'source' => 'High ground', 'modifier' => 1 }])
      expect(result).to eq([{ source: 'High ground', modifier: 1 }])
    end

    it 'drops plain string entries instead of crashing' do
      result = described_class.normalize(['flanking', { 'source' => 'High ground', 'modifier' => 1 }])
      expect(result).to eq([{ source: 'High ground', modifier: 1 }])
    end

    it 'drops nil + non-hash entries' do
      result = described_class.normalize([nil, 42, ['flanking'], { 'source' => 'kept' }])
      expect(result).to eq([{ source: 'kept' }])
    end

    it 'returns [] for nil input' do
      expect(described_class.normalize(nil)).to eq([])
    end
  end
end
