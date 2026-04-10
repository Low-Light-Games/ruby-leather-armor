# frozen_string_literal: true

require "rails_helper"

RSpec.describe SheetPresenter, type: :model do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet)     { create(:adventure_sheet, adventure: adventure) }

  subject(:presenter) do
    described_class.new(
      sheet,
      feat_rel:  sheet.adventure_sheet_feats,
      spell_rel: sheet.adventure_sheet_spells,
      item_rel:  sheet.adventure_sheet_items
    )
  end

  describe "#as_json" do
    it "returns a Hash" do
      expect(presenter.as_json).to be_a(Hash)
    end

    it "includes standard sheet attributes" do
      json = presenter.as_json
      expect(json).to include("id", "name", "level")
    end

    it "includes feats, knownSpells, spellbook, and items inside details" do
      json = presenter.as_json
      details = json["details"] || {}
      expect(details).to include("feats", "knownSpells", "spellbook", "items")
    end

    it "returns an empty feats array when no feats are attached" do
      expect(presenter.as_json.dig("details", "feats")).to eq([])
    end

    it "returns empty spell arrays when no spells are attached" do
      expect(presenter.as_json.dig("details", "knownSpells")).to eq([])
      expect(presenter.as_json.dig("details", "spellbook")).to eq([])
    end

    it "returns an empty items array when no items are attached" do
      expect(presenter.as_json.dig("details", "items")).to eq([])
    end
  end
end
