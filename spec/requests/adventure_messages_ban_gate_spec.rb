# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adventure messages ban gate", type: :request do
  let(:story)     { create(:story) }
  let(:user)      { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }

  before { sign_in_via_session(user) }

  describe "POST /adventures/:id/messages" do
    context "when the user is not banned" do
      it "accepts the message (202)" do
        allow(PipelineJob).to receive(:perform_later)
        post "/adventures/#{adventure.id}/messages",
             params: { content: "I look around the room." },
             headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:accepted)
      end
    end

    context "when the user is banned" do
      let(:user) { create(:user, :banned) }

      it "returns 403" do
        post "/adventures/#{adventure.id}/messages",
             params: { content: "I look around the room." },
             headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:forbidden)
      end

      it "returns a banned flag in the response" do
        post "/adventures/#{adventure.id}/messages",
             params: { content: "I look around the room." },
             headers: { "Accept" => "application/json" }
        expect(JSON.parse(response.body)).to include("banned" => true)
      end

      it "does not enqueue a pipeline job" do
        expect(PipelineJob).not_to receive(:perform_later)
        post "/adventures/#{adventure.id}/messages",
             params: { content: "I look around the room." },
             headers: { "Accept" => "application/json" }
      end
    end
  end

  describe "GET /adventures/:id/messages" do
    context "when the user is banned" do
      let(:user) { create(:user, :banned) }

      it "returns 403" do
        get "/adventures/#{adventure.id}/messages",
            headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when the user is not banned" do
      it "returns 200" do
        get "/adventures/#{adventure.id}/messages",
            headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
