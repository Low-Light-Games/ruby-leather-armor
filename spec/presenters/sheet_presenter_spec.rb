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
      expect(shield["duration_label"]).to eq("12 min remaining")

      blessing = active_buffs.find { |b| b["source"] == "blessing" }
      expect(blessing["remaining_hours"]).to be_nil
      expect(blessing["duration_label"]).to eq("Sustained")
    end

    it "formats sub-five-minute durations as m:ss" do
      adventure.update!(time_context: adventure.time_context.merge("current_hour" => 8.0))
      sheet.update!(
        active_buffs: [
          {
            "source" => "blink",
            "bonus_type" => "dodge",
            "target" => "ac",
            "value" => 1,
            "expires_at_game_hours" => 8.0125
          },
          {
            "source" => "shield",
            "bonus_type" => "shield",
            "target" => "ac",
            "value" => 4,
            "expires_at_game_hours" => 8.025
          },
          {
            "source" => "haste",
            "bonus_type" => "enhancement",
            "target" => "speed",
            "value" => 30,
            "expires_at_game_hours" => 8.07
          }
        ]
      )

      active_buffs = presenter.as_json.fetch("active_buffs").index_by { |b| b["source"] }

      expect(active_buffs.fetch("blink")["duration_label"]).to eq("0:45 remaining")
      expect(active_buffs.fetch("shield")["duration_label"]).to eq("1:30 remaining")
      expect(active_buffs.fetch("haste")["duration_label"]).to eq("4:12 remaining")
    end

    it "switches from m:ss to explicit minutes at five minutes" do
      adventure.update!(time_context: adventure.time_context.merge("current_hour" => 8.0))
      sheet.update!(
        active_buffs: [
          {
            "source" => "blur",
            "bonus_type" => "concealment",
            "target" => "ac",
            "value" => 20,
            "expires_at_game_hours" => 8.0830556
          },
          {
            "source" => "mage_armor",
            "bonus_type" => "armor",
            "target" => "ac",
            "value" => 4,
            "expires_at_game_hours" => 8.0833333
          }
        ]
      )

      active_buffs = presenter.as_json.fetch("active_buffs").index_by { |b| b["source"] }

      expect(active_buffs.fetch("blur")["duration_label"]).to eq("4:59 remaining")
      expect(active_buffs.fetch("mage_armor")["duration_label"]).to eq("5 min remaining")
    end

    it "formats hour-scale durations with explicit hr/min units" do
      adventure.update!(time_context: adventure.time_context.merge("current_hour" => 8.0))
      sheet.update!(
        active_buffs: [
          {
            "source" => "stoneskin",
            "bonus_type" => "enhancement",
            "target" => "ac",
            "value" => 2,
            "expires_at_game_hours" => 9.0
          },
          {
            "source" => "heroism",
            "bonus_type" => "morale",
            "target" => "saves",
            "value" => 2,
            "expires_at_game_hours" => 9.2
          }
        ]
      )

      active_buffs = presenter.as_json.fetch("active_buffs").index_by { |b| b["source"] }

      expect(active_buffs.fetch("stoneskin")["duration_label"]).to eq("1 hr remaining")
      expect(active_buffs.fetch("heroism")["duration_label"]).to eq("1 hr 12 min remaining")
    end
  end
end
