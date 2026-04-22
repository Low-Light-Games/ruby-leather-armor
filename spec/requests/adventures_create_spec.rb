require "rails_helper"

RSpec.describe "Adventures create", type: :request do
  let(:user)  { create(:user) }
  let(:story) { create(:story) }
  let(:sheet) { create(:sheet, user: user) }

  before do
    sign_in_via_session(user)
    allow_any_instance_of(DungeonMaster::Embellisher).to receive(:run)
  end

  it "skips the world sanity check by default" do
    expect do
      post "/adventures",
           params: { story_id: story.id, sheet_id: sheet.id },
           as: :json
    end.to change(Adventure, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(Adventure.order(:id).last.skip_world_sanity_check).to be(true)
    expect(JSON.parse(response.body).fetch("skip_world_sanity_check")).to be(true)
  end

  it "lets the player turn the world sanity check back on" do
    post "/adventures",
         params: { story_id: story.id, sheet_id: sheet.id, skip_world_sanity_check: false },
         as: :json

    expect(response).to have_http_status(:created)
    expect(Adventure.order(:id).last.skip_world_sanity_check).to be(false)
    expect(JSON.parse(response.body).fetch("skip_world_sanity_check")).to be(false)
  end
end
