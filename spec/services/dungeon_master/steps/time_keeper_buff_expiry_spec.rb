# frozen_string_literal: true

require "rails_helper"

# Tests the TimeKeeper#expire_elapsed_buffs private method via a minimal test
# harness that includes the module directly, avoiding full pipeline wiring.
RSpec.describe "DungeonMaster::Steps::TimeKeeper — expire_elapsed_buffs", type: :service do
  # ── Harness ────────────────────────────────────────────────────────────────
  let(:harness_class) do
    Class.new do
      include DungeonMaster::Steps::TimeKeeper

      attr_accessor :adventure, :sheet, :log

      def initialize(adventure:, sheet:, log:)
        @adventure = adventure
        @sheet     = sheet
        @log       = log
      end

      # Expose the private method for testing
      def call_expire(time_ctx)
        expire_elapsed_buffs(time_ctx)
      end
    end
  end

  # ── DB records ─────────────────────────────────────────────────────────────
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  let(:sheet) do
    create(:adventure_sheet,
      adventure:       adventure,
      strength:        10, dexterity:       10, constitution:    10,
      intelligence:    10, wisdom:          10, charisma:        10,
      race:            "human", character_class: "fighter", level: 1
    )
  end

  let(:log) { instance_double(DungeonMaster::Logging, log!: nil, play_log!: nil) }

  let(:harness) { harness_class.new(adventure: adventure, sheet: sheet, log: log) }

  # ── Time context helpers ────────────────────────────────────────────────────
  # adventure_day 1, current_hour 10.0 → current_game_hours = 10.0
  let(:time_ctx) { { "adventure_day" => 1, "current_hour" => 10.0 } }

  # ── Buff helpers ────────────────────────────────────────────────────────────
  def buff(source:, expires_at:)
    { "source" => source, "bonus_type" => "armor", "target" => "ac", "value" => 4,
      "expires_at_game_hours" => expires_at }
  end

  def set_buffs(buffs)
    sheet.update_column(:active_buffs, buffs)
    sheet.reload
  end

  # ── Behaviour ──────────────────────────────────────────────────────────────

  context "when no buffs are present" do
    before { set_buffs([]) }

    it "does not mutate the sheet" do
      expect(sheet).not_to receive(:update!)
      harness.call_expire(time_ctx)
    end
  end

  context "when all buffs are still valid (expire in the future)" do
    before { set_buffs([buff(source: "mage_armor", expires_at: 15.0)]) }

    it "does not remove any buffs" do
      harness.call_expire(time_ctx)
      sheet.reload
      expect(sheet.active_buffs.length).to eq(1)
    end
  end

  context "when one buff has expired (expires_at <= current_hour)" do
    before do
      set_buffs([
        buff(source: "shield",     expires_at: 9.5),   # expired (9.5 <= 10.0)
        buff(source: "mage_armor", expires_at: 15.0)   # still active
      ])
    end

    it "removes only the expired buff" do
      harness.call_expire(time_ctx)
      sheet.reload
      sources = sheet.active_buffs.map { |b| b["source"] }
      expect(sources).to eq(["mage_armor"])
    end

    it "logs the expiry" do
      expect(log).to receive(:log!).with(:info, /expired buffs.*shield/)
      harness.call_expire(time_ctx)
    end
  end

  context "when all buffs have expired" do
    before do
      set_buffs([
        buff(source: "shield",     expires_at: 8.0),
        buff(source: "mage_armor", expires_at: 9.0)
      ])
    end

    it "empties active_buffs" do
      harness.call_expire(time_ctx)
      sheet.reload
      expect(sheet.active_buffs).to eq([])
    end
  end

  context "when a buff has no expires_at (sustained / permanent)" do
    before do
      set_buffs([
        { "source" => "ring_of_protection", "bonus_type" => "deflection", "target" => "ac",
          "value" => 2, "expires_at_game_hours" => nil }
      ])
    end

    it "leaves sustained buffs untouched" do
      harness.call_expire(time_ctx)
      sheet.reload
      expect(sheet.active_buffs.length).to eq(1)
    end
  end

  context "when a buff expires exactly at the current hour" do
    before { set_buffs([buff(source: "shield", expires_at: 10.0)]) }

    it "removes the buff (expired at boundary)" do
      harness.call_expire(time_ctx)
      sheet.reload
      expect(sheet.active_buffs).to eq([])
    end
  end

  context "when sheet does not support active_buffs" do
    it "returns without error" do
      bare = instance_double("CreatureSheet")
      allow(bare).to receive(:respond_to?).with(:active_buffs).and_return(false)
      harness2 = harness_class.new(adventure: adventure, sheet: bare, log: log)
      expect { harness2.call_expire(time_ctx) }.not_to raise_error
    end
  end
end
