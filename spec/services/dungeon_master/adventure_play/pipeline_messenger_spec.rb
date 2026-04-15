require "rails_helper"

RSpec.describe DungeonMaster::AdventurePlay::PipelineMessenger, type: :service do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:log)       { instance_double(DungeonMaster::Logging, registry_entry_uuid: "registry-123") }
  let(:messenger) { described_class.new(adventure: adventure, log: log, user: user) }

  describe "#persist_event_messages" do
    it "marks the adventure ended for player death before persisting the message" do
      persisted_message = nil

      allow(messenger).to receive(:persist_message).and_wrap_original do |orig, **kwargs|
        persisted_message = orig.call(**kwargs)
        expect(adventure.reload.end_reason).to eq("player_death")
        persisted_message
      end

      messages = messenger.send(:persist_event_messages, { player_death: true })

      expect(messages.map(&:message_type)).to eq(["player_death"])
      expect(adventure.reload).to be_ended
      expect(adventure.end_reason).to eq("player_death")
    end

    it "marks the adventure ended for adventure completion" do
      messenger.send(:persist_event_messages, { adventure_complete: true })

      expect(adventure.reload).to be_ended
      expect(adventure.end_reason).to eq("adventure_complete")
    end

    it "does not end the adventure for player incapacitation alone" do
      messenger.send(:persist_event_messages, { player_incapacitated: true })

      expect(adventure.reload).not_to be_ended
    end

    it "does not rewrite the end reason once set" do
      messenger.send(:persist_event_messages, { player_death: true })
      ended_at = adventure.reload.ended_at

      messenger.send(:persist_event_messages, { adventure_complete: true })

      adventure.reload
      expect(adventure.ended_at).to eq(ended_at)
      expect(adventure.end_reason).to eq("player_death")
    end
  end
end
