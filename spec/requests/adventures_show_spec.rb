require "rails_helper"

RSpec.describe "Adventures show", type: :request do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }

  before { sign_in_via_session(user) }

  it "includes ended state fields in the JSON response" do
    adventure.update!(ended_at: Time.zone.parse("2026-04-15 12:34:00 UTC"), end_reason: "player_death")

    get "/adventures/#{adventure.id}.json", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["ended"]).to be true
    expect(body["ended_at"]).to be_present
    expect(body["end_reason"]).to eq("player_death")
  end
end
