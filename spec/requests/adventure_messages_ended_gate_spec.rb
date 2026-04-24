require "rails_helper"

RSpec.describe "Adventure Messages ended gate", type: :request do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story, ended_at: Time.current, end_reason: "player_death") }

  before { sign_in(user) }

  it "rejects POST /messages with a stable ended error" do
    post "/adventures/#{adventure.id}/messages",
         params: { content: "I keep walking." },
         headers: { "Accept" => "application/json" }

    expect(response.status).to eq(422)
    body = JSON.parse(response.body)
    expect(body["error_code"]).to eq("adventure_ended")
    expect(body["error"]).to include("has ended")
  end

  it "rejects POST /messages/roll with a stable ended error" do
    post "/adventures/#{adventure.id}/messages/roll",
         params: { roll_value: 15, roll_description: "Attack roll", resolution_method: "manual" },
         headers: { "Accept" => "application/json" }

    expect(response.status).to eq(422)
    body = JSON.parse(response.body)
    expect(body["error_code"]).to eq("adventure_ended")
  end

  it "rejects POST /messages/initiative with a stable ended error" do
    post "/adventures/#{adventure.id}/messages/initiative",
         params: { initiative: 12 },
         headers: { "Accept" => "application/json" }

    expect(response.status).to eq(422)
    body = JSON.parse(response.body)
    expect(body["error_code"]).to eq("adventure_ended")
  end
end
