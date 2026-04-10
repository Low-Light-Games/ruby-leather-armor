# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adventures::Bootstrap, type: :service do
  let(:user)  { create(:user) }
  let(:story) { create(:story) }
  let(:sheet) { create(:sheet, user: user) }

  before do
    allow_any_instance_of(DungeonMaster::Embellisher).to receive(:run)
  end

  subject(:bootstrap) do
    described_class.new(story: story, sheet: sheet, user: user)
  end

  describe "#call" do
    it "creates an Adventure for the user and story" do
      expect { bootstrap.call }.to change { Adventure.count }.by(1)
      adventure = Adventure.last
      expect(adventure.user).to eq(user)
      expect(adventure.story).to eq(story)
    end

    it "returns the persisted, reloaded Adventure" do
      result = bootstrap.call
      expect(result).to be_a(Adventure)
      expect(result).to be_persisted
    end

    it "creates an AdventureSheet via SheetCopier" do
      expect { bootstrap.call }.to change { AdventureSheet.count }.by(1)
    end

    it "seeds plot_state with the expected tracking keys" do
      adventure = bootstrap.call
      expect(adventure.plot_state.keys).to include(
        "discovered_clues", "attempted_clues", "reached_milestones",
        "npc_met", "npc_attitudes", "custom_facts"
      )
    end

    it "creates an opening DM message when none exists" do
      expect { bootstrap.call }.to change { AdventureMessage.count }.by(1)
      msg = AdventureMessage.last
      expect(msg.role).to eq("dm")
      expect(msg.message_type).to eq("narrative")
    end

    it "does not create a second opening message if one already exists" do
      adventure = bootstrap.call
      expect { bootstrap.call }.not_to(change { AdventureMessage.count })
    end

    context "with directed_dm: true" do
      subject(:bootstrap) do
        described_class.new(story: story, sheet: sheet, user: user, directed_dm: true)
      end

      it "sets directed_dm on the adventure" do
        adventure = bootstrap.call
        expect(adventure.directed_dm).to be(true)
      end
    end

    context "when Embellisher fails" do
      before do
        allow_any_instance_of(DungeonMaster::Embellisher).to receive(:run)
          .and_raise(DungeonMaster::AiError, "timeout")
      end

      it "still creates the adventure and does not re-raise" do
        expect { bootstrap.call }.to change { Adventure.count }.by(1)
      end
    end
  end
end
