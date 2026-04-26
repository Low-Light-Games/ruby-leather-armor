require "rails_helper"

RSpec.describe "Adventure Messages flood control", type: :request do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  before do
    sign_in(user)
  end

  describe "prompt backlog admission" do
    before do
      allow(PipelineJob).to receive(:perform_later)
    end

    it "returns 429 without persisting the player prompt when the backlog gate rejects" do
      allow(DungeonMaster::FloodControl).to receive(:admit_prompt_submission)
        .and_raise(DungeonMaster::FloodControl::PromptBacklogExceeded, "Wait your turn.")

      expect do
        post "/adventures/#{adventure.id}/messages",
             params: { content: "I search the room." },
             headers: { "Accept" => "application/json" }
      end.not_to change { adventure.adventure_messages.count }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["X-RateLimit-Reason"]).to eq("prompt_backlog")

      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("prompt_backlog")
      expect(body["error"]).to eq("Wait your turn.")
    end
  end

  describe "roll continuation validation" do
    before do
      allow(RollPipelineJob).to receive(:perform_later)
    end

    it "rejects rolls when no pending roll request exists" do
      post "/adventures/#{adventure.id}/messages/roll",
           params: { roll_value: 15, roll_description: "Perception check", resolution_method: "roll" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("roll_not_requested")
    end

    it "accepts a roll continuation without consuming the prompt backlog gate" do
      adventure.adventure_messages.create!(
        role: "dm",
        content: "Roll Stealth.",
        message_type: "roll_request",
        metadata: { "intent" => { "intention" => "Hide in shadows" } }
      )

      expect(DungeonMaster::FloodControl).not_to receive(:admit_prompt_submission)

      post "/adventures/#{adventure.id}/messages/roll",
           params: { roll_value: 15, roll_description: "Stealth", resolution_method: "roll" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:accepted)
      expect(adventure.adventure_messages.from_players.newest_first.first.message_type).to eq("roll_result")
    end
  end

  describe "initiative continuation validation" do
    before do
      allow(InitiativePipelineJob).to receive(:perform_later)
    end

    it "rejects initiative when no pending initiative request exists" do
      post "/adventures/#{adventure.id}/messages/initiative",
           params: { initiative: 12 },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("initiative_not_requested")
    end

    it "accepts initiative continuation without consuming the prompt backlog gate" do
      adventure.adventure_messages.create!(
        role: "dm",
        content: "Roll initiative!",
        message_type: "initiative_request",
        metadata: { "creature_data" => [{ "name" => "Goblin" }] }
      )

      expect(DungeonMaster::FloodControl).not_to receive(:admit_prompt_submission)

      post "/adventures/#{adventure.id}/messages/initiative",
           params: { initiative: 12 },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:accepted)
      expect(adventure.adventure_messages.from_players.newest_first.first.message_type).to eq("initiative_result")
    end
  end

  describe "Rack::Attack throttles" do
    it "returns a user_rate 429 after the per-user burst is exceeded" do
      12.times do
        post "/adventures/#{adventure.id}/messages/roll",
             params: { roll_value: 15, roll_description: "Perception check", resolution_method: "roll" },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      post "/adventures/#{adventure.id}/messages/roll",
           params: { roll_value: 15, roll_description: "Perception check", resolution_method: "roll" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["X-RateLimit-Reason"]).to eq("user_rate")
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("user_rate")
    end

    it "returns an ip_rate 429 only after aggregate traffic exceeds the looser IP ceiling" do
      users = create_list(:user, 11, :password_auth)

      users.first(10).each do |other_user|
        other_adventure = create(:adventure, user: other_user, story: story)
        sign_in(other_user)

        11.times do
          post "/adventures/#{other_adventure.id}/messages/roll",
               params: { roll_value: 15, roll_description: "Perception check", resolution_method: "roll" },
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      sign_in(users.last)
      last_adventure = create(:adventure, user: users.last, story: story)

      10.times do
        post "/adventures/#{last_adventure.id}/messages/roll",
             params: { roll_value: 15, roll_description: "Perception check", resolution_method: "roll" },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      post "/adventures/#{last_adventure.id}/messages/roll",
           params: { roll_value: 15, roll_description: "Perception check", resolution_method: "roll" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["X-RateLimit-Reason"]).to eq("ip_rate")
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("ip_rate")
    end
  end
end
