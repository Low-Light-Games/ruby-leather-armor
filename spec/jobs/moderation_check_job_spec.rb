require "rails_helper"

RSpec.describe ModerationCheckJob, type: :job do
  let(:user)         { create(:user, trusted: true) }
  let(:player_input) { "Some player text." }

  describe "#perform" do
    it "calls ModerationService with the correct user and input" do
      expect(DungeonMaster::ModerationService).to receive(:call)
        .with(player_input, user: user)
        .and_return(DungeonMaster::ModerationService::Result.new(flagged: false, response_text: nil))

      described_class.perform_now(user.id, player_input)
    end

    it "discards itself when the user no longer exists" do
      expect { described_class.perform_now(-1, player_input) }.not_to raise_error
    end
  end
end
