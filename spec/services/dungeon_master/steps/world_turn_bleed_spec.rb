# frozen_string_literal: true

require "rails_helper"

# Unit tests for the dying bleed-out mechanic in DungeonMaster::Steps::WorldTurn.
# We exercise apply_dying_bleed! in isolation via a minimal host object that
# includes the module and stubs dependencies we don't need to exercise here.
RSpec.describe "DungeonMaster::Steps::WorldTurn dying bleed-out", type: :service do
  let(:host_class) do
    Class.new do
      include DungeonMaster::Steps::WorldTurn
      include DungeonMaster::Mutations

      attr_accessor :adventure, :sheet

      def initialize(adventure:, sheet:)
        @adventure       = adventure
        @sheet           = sheet
        @loop            = nil
        @on_sheet_update = nil
        @log             = OpenStruct.new(log!: nil, ai_log!: nil)
      end
    end
  end

  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) do
    create(:adventure, user: user, story: story, combat_context: {
      "active" => true, "round" => 1, "current_turn" => "Player",
      "turn_order" => ["Player"], "participants" => [
        { "name" => "Player", "type" => "player", "hp" => -3, "max_hp" => 10,
          "initiative" => 5, "conditions" => [] }
      ]
    })
  end

  # CON 10 → modifier 0; death threshold: hp <= -10
  let(:sheet) do
    create(:adventure_sheet, adventure: adventure,
      constitution: 10, hp: -3, max_hp: 10,
      strength: 10, dexterity: 10, intelligence: 10, wisdom: 10, charisma: 10,
      race: "human", character_class: "fighter", level: 1)
  end

  subject(:host) { host_class.new(adventure: adventure, sheet: sheet) }

  describe "#apply_dying_bleed!" do
    let(:result) { { mutations: {} } }

    context "when the -1 HP bleed reaches the death threshold (hp = -9 → -10 = −CON)" do
      before { sheet.update_column(:hp, -9) }

      it "marks player_death, sets active: false in mutations, and returns the result" do
        allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(1)

        returned = host.send(:apply_dying_bleed!, result)
        expect(returned).not_to be_nil
        expect(returned[:player_death]).to be true
        expect(sheet.reload.hp).to eq(-10)  # clamped to -CON
        expect(returned[:mutations]).to have_key("combat_state_advancement")
      end
    end

    context "when the player fails the stabilization roll (roll + mod < 10)" do
      it "applies -1 HP bleed, returns nil so NPC resolution continues" do
        allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(1)  # 1 + 0 = 1 < 10

        returned = host.send(:apply_dying_bleed!, result)
        expect(returned).to be_nil
        expect(sheet.reload.hp).to eq(-4)
        expect(Array(sheet.reload.conditions)).not_to include("stabilized")
      end
    end

    context "when the player passes the stabilization roll (roll + mod >= 10)" do
      it "applies -1 HP bleed, adds stabilized condition, returns nil" do
        allow(DungeonMaster::Rolls::CombatDice).to receive(:roll_d20).and_return(10)  # 10 + 0 = 10 >= 10

        returned = host.send(:apply_dying_bleed!, result)
        expect(returned).to be_nil
        expect(sheet.reload.hp).to eq(-4)
        expect(Array(sheet.reload.conditions)).to include("stabilized")
      end
    end
  end
end
