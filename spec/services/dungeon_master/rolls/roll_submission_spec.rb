# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DungeonMaster::Rolls::RollSubmission do
  describe '#to_a' do
    it 'normalizes a top-level :rolls array' do
      params = { rolls: [
        { roll_value: 17, roll_description: ' Climb ', resolution_method: 'manual', request_id: 'req-1' },
        { roll_value: 5,  roll_description: 'Reflex save' }
      ] }
      out = described_class.new(params).to_a

      expect(out.length).to eq(2)
      expect(out.first).to include(roll_value: 17, roll_description: 'Climb',
                                   resolution_method: 'manual', request_id: 'req-1')
      expect(out.last).to include(roll_value: 5, roll_description: 'Reflex save', request_id: nil)
    end

    it 'falls back to flat :roll_value/:roll_description params' do
      out = described_class.new({ roll_value: 12, roll_description: 'Stealth' }).to_a
      expect(out).to eq([{ roll_value: 12, roll_description: 'Stealth',
                           resolution_method: nil, request_id: nil }])
    end

    it 'defaults roll_description when blank' do
      out = described_class.new({ roll_value: 1 }).to_a
      expect(out.first[:roll_description]).to eq('unknown check')
    end

    it 'raises InvalidValueError when any value is out of range' do
      params = { rolls: [{ roll_value: 17 }, { roll_value: 999 }] }
      expect { described_class.new(params).to_a }
        .to raise_error(described_class::InvalidValueError, /must be between -100 and 100/)
    end
  end
end
