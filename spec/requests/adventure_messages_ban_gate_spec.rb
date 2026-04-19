require "rails_helper"

RSpec.describe "Adventure Messages ban gate", type: :request do
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  before { sign_in_via_session(user) }

  context "when the user is banned" do
    let(:user) { create(:user, banned: true) }

    describe "POST /adventures/:id/messages" do
      it "returns 403 with a banned payload" do
        post "/adventures/#{adventure.id}/messages",
             params: { content: "I try to open the door." },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body["banned"]).to be true
        expect(body["message"]).to include("appeals@leatheramor.io")
      end
    end

    describe "POST /adventures/:id/messages/roll" do
      it "returns 403" do
        post "/adventures/#{adventure.id}/messages/roll",
             params: { roll_value: 15, roll_description: "Perception check",
                       resolution_method: "roll" },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /adventures/:id/messages/initiative" do
      it "returns 403" do
        post "/adventures/#{adventure.id}/messages/initiative",
             params: { initiative: 12 },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  context "when the user is not banned" do
    let(:user) { create(:user) }

    it "does not block access to GET /messages" do
      get "/adventures/#{adventure.id}/messages",
          headers: { "Accept" => "application/json" }

      expect(response).not_to have_http_status(:forbidden)
    end

    it "does not block POST /messages (proceeds past the ban gate)" do
      # We only care it doesn't return 403 — the pipeline itself is not run in request specs.
      allow_any_instance_of(DungeonMasterService).to receive(:prepare_prompt) do
        adventure.adventure_messages.create!(
          role: "player", content: "I open the door.", message_type: "narrative", metadata: {})
      end
      allow(PipelineJob).to receive(:perform_later)

      post "/adventures/#{adventure.id}/messages",
           params: { content: "I open the door." },
           headers: { "Accept" => "application/json" }

      expect(response).not_to have_http_status(:forbidden)
    end

    describe "POST /adventures/:id/messages/roll" do
      before do
        allow_any_instance_of(DungeonMasterService).to receive(:prepare_roll) do |service, rolls|
          adventure.adventure_messages.create!(
            role: "player",
            content: DungeonMaster::Rolls::RollResultsText.format(rolls),
            message_type: "roll_result",
            metadata: { "rolls" => rolls }
          )
        end
        allow(RollPipelineJob).to receive(:perform_later)
      end

      it "accepts a zero roll total" do
        post "/adventures/#{adventure.id}/messages/roll",
             params: { roll_value: 0, roll_description: "Attack roll", resolution_method: "manual" },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:accepted)
      end

      it "accepts a negative roll total" do
        post "/adventures/#{adventure.id}/messages/roll",
             params: { roll_value: -3, roll_description: "Attack roll", resolution_method: "manual" },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:accepted)
      end
    end
  end
end
