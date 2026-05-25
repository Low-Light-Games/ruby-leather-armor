require "rails_helper"

RSpec.describe "Adventure Messages user attribution", type: :request do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  before do
    sign_in(user)
    allow(PipelineJob).to receive(:perform_later)
  end

  describe "POST /adventures/:id/messages" do
    it "stamps the persisted player message with user_id" do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I sneak past the goblin." },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:accepted)

      msg = adventure.adventure_messages.from_players.newest_first.first
      expect(msg.user_id).to eq(user.id)
    end
  end
end
