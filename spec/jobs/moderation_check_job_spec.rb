# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModerationCheckJob, type: :job do
  include ActiveJob::TestHelper

  let(:user)  { create(:user, :trusted) }
  let(:input) { "I try to pick the lock." }

  describe "#perform" do
    it "calls ModerationService with the user and input" do
      expect(DungeonMaster::ModerationService).to receive(:call).with(input, user: user)
      described_class.perform_now(user.id, input)
    end

    it "discards the job when the user no longer exists" do
      expect {
        described_class.perform_now(-1, input)
      }.not_to raise_error
    end

    context "when the input is flagged" do
      before do
        allow(DungeonMaster::ModerationService).to receive(:call) do |_input, user:|
          user.update!(moderation_strikes: user.moderation_strikes + 1, trusted: false)
          DungeonMaster::ModerationService::Result.new(flagged: true,
            response_text: "flagged")
        end
      end

      it "revokes trust on the user" do
        described_class.perform_now(user.id, input)
        expect(user.reload.trusted?).to be false
      end
    end

    context "when the input is clean" do
      before do
        allow(DungeonMaster::ModerationService).to receive(:call)
          .and_return(DungeonMaster::ModerationService::Result.new(flagged: false, response_text: nil))
      end

      it "does not modify the user" do
        expect { described_class.perform_now(user.id, input) }
          .not_to change { user.reload.attributes.slice("trusted", "banned", "moderation_strikes") }
      end
    end
  end
end
