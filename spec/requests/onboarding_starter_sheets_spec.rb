require "rails_helper"

RSpec.describe "Onboarding starter sheets", type: :request do
  let(:user) { create(:user, :password_auth) }
  let!(:story) { create(:story) }

  before do
    sign_in(user)
    allow(Story).to receive_message_chain(:kept, :order, :first).and_return(story)
  end

  it "creates a starter sheet instead of a visible custom sheet" do
    adventure = create(:adventure, user: user, story: story)
    bootstrap = instance_double(Adventures::Bootstrap, call: adventure)
    allow(Adventures::Bootstrap).to receive(:new).and_return(bootstrap)

    expect {
      post "/onboarding/complete", params: { character_type: "rogue" }, as: :json
    }.to change { user.sheets.starter.count }.by(1)
      .and(change { user.sheets.custom.count }.by(0))

    expect(response).to have_http_status(:created)

    created_sheet = user.sheets.find_by!(starter_key: "rogue")
    expect(created_sheet).to be_starter
    expect(created_sheet.name).to eq("Maren Ashwick")
  end

  it "reuses the same starter sheet when onboarding is repeated" do
    bootstrap = instance_double(Adventures::Bootstrap, call: create(:adventure, user: user, story: story))
    allow(Adventures::Bootstrap).to receive(:new).and_return(bootstrap)

    post "/onboarding/complete", params: { character_type: "fighter" }, as: :json
    expect(response).to have_http_status(:created)

    expect {
      post "/onboarding/complete", params: { character_type: "fighter" }, as: :json
    }.not_to change { user.sheets.where(starter_key: "fighter").count }
  end
end
