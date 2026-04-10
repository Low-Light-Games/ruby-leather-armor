# frozen_string_literal: true

require "rails_helper"

# Tests the SheetCurrency concern through the three models that include it.
# Behavioural coverage is intentionally thin here — the Currency value object
# spec owns the arithmetic and conversion logic.  These tests verify that the
# concern is correctly wired and delegates to Currency.
RSpec.describe SheetCurrency do
  shared_examples "sheet currency behaviour" do |factory_name|
    subject(:record) { build(factory_name, currency: { "gold" => 4, "silver" => 6, "copper" => 0, "platinum" => 1 }) }

    describe "CURRENCY_KEYS constant" do
      it "is defined on the class" do
        expect(record.class::CURRENCY_KEYS).to eq(Currency::KEYS)
      end
    end

    describe "#currency_value" do
      it "returns a Currency instance" do
        expect(record.currency_value).to be_a(Currency)
      end

      it "reflects the stored hash values" do
        expect(record.currency_value.gold).to eq(4)
        expect(record.currency_value.platinum).to eq(1)
      end
    end

    describe "#total_coins" do
      it "returns the sum of all coin counts" do
        expect(record.total_coins).to eq(11)
      end

      it "returns 0 when currency is nil" do
        record.currency = nil
        expect(record.total_coins).to eq(0)
      end
    end

    describe "#total_gp_value" do
      it "converts denominations to gold-piece equivalent" do
        # 4gp + 0.6gp (6sp) + 0cp + 10gp (1pp) = 14.6
        expect(record.total_gp_value).to be_within(0.001).of(14.6)
      end
    end
  end

  describe Sheet do
    it_behaves_like "sheet currency behaviour", :sheet
  end

  describe AdventureSheet do
    it_behaves_like "sheet currency behaviour", :adventure_sheet
  end
end
