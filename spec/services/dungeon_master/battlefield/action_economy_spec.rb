# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Battlefield::ActionEconomy, type: :service do
  describe ".apply_delta!" do
    let(:fresh_pool) do
      {
        "standard_available" => true,
        "move_available" => true,
        "swift_available" => true,
        "full_round_claimed" => false
      }
    end

    it "rejects full_round after move was spent" do
      econ = fresh_pool.merge("move_available" => false)
      expect do
        described_class.apply_delta!(econ, { "spend_full_round" => true })
      end.to raise_error(ArgumentError, /full-round requires both standard and move/)
    end

    it "rejects full_round after standard was spent" do
      econ = fresh_pool.merge("standard_available" => false)
      expect do
        described_class.apply_delta!(econ, { "spend_full_round" => true })
      end.to raise_error(ArgumentError, /full-round requires both standard and move/)
    end

    it "allows full_round when both slots are still available" do
      out = described_class.apply_delta!(fresh_pool, { "spend_full_round" => true })
      expect(out["full_round_claimed"]).to be true
      expect(out["standard_available"]).to be false
      expect(out["move_available"]).to be false
    end
  end
end
