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

    it "filters expired buffs and adds duration fields to active buffs" do
      adventure.update!(time_context: adventure.time_context.merge("current_hour" => 8.0))
      sheet.update!(
        active_buffs: [
          {
            "source" => "shield",
            "bonus_type" => "shield",
            "target" => "ac",
            "value" => 4,
            "expires_at_game_hours" => 8.2
          },
          {
            "source" => "stale_haste",
            "bonus_type" => "enhancement",
            "target" => "speed",
            "value" => 30,
            "expires_at_game_hours" => 7.9
          },
          {
            "source" => "blessing",
            "bonus_type" => "morale",
            "target" => "saves",
            "value" => 1
          }
        ]
      )

      active_buffs = presenter.as_json.fetch("active_buffs")

      expect(active_buffs.map { |b| b["source"] }).to contain_exactly("shield", "blessing")

      shield = active_buffs.find { |b| b["source"] == "shield" }
      expect(shield["remaining_hours"]).to be_within(0.001).of(0.2)
      expect(shield["duration_label"]).to eq("12m remaining")

      blessing = active_buffs.find { |b| b["source"] == "blessing" }
      expect(blessing["remaining_hours"]).to be_nil
      expect(blessing["duration_label"]).to eq("Sustained")
    end
  end
end
