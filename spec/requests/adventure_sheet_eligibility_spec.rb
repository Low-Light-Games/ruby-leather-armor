require "rails_helper"

RSpec.describe "Adventure sheet eligibility", type: :request do
  let(:story) { create(:story) }
  let(:free_user) { create(:user, :password_auth) }
  let(:paid_user) { create(:user, :password_auth, :paid) }
  let(:admin_user) { create(:user, :password_auth, :admin) }

  def stub_bootstrap_for(user:, story:, sheet:)
    adventure = create(:adventure, user: user, story: story)
    create(
      :adventure_sheet,
      adventure: adventure,
      sheet_id: sheet.id,
      name: sheet.name,
      description: sheet.description,
      level: sheet.level,
      character_class: sheet.character_class,
      race: sheet.race,
      strength: sheet.strength,
      dexterity: sheet.dexterity,
      constitution: sheet.constitution,
      intelligence: sheet.intelligence,
      wisdom: sheet.wisdom,
      charisma: sheet.charisma
    )

    bootstrap = instance_double(Adventures::Bootstrap, call: adventure)
    allow(Adventures::Bootstrap).to receive(:new).and_return(bootstrap)
  end

  describe "POST /adventures" do
    it "allows free users to start with starter sheets" do
      starter_sheet = create(:sheet, :starter_rogue, user: free_user)
      sign_in(free_user)
      stub_bootstrap_for(user: free_user, story: story, sheet: starter_sheet)

      post "/adventures", params: { story_id: story.id, sheet_id: starter_sheet.id }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "rejects free users using custom sheets" do
      custom_sheet = create(:sheet, user: free_user)
      sign_in(free_user)

      post "/adventures", params: { story_id: story.id, sheet_id: custom_sheet.id }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to include("error" => "Subscribe to play adventures with your custom character.")
    end

    it "allows paid users to start with custom sheets" do
      custom_sheet = create(:sheet, user: paid_user)
      sign_in(paid_user)
      stub_bootstrap_for(user: paid_user, story: story, sheet: custom_sheet)

      post "/adventures", params: { story_id: story.id, sheet_id: custom_sheet.id }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "rejects paid users using starter sheets" do
      starter_sheet = create(:sheet, :starter_fighter, user: paid_user)
      sign_in(paid_user)

      post "/adventures", params: { story_id: story.id, sheet_id: starter_sheet.id }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to include(
        "error" => "Starter characters are reserved for free users. Choose one of your custom sheets instead."
      )
    end

    it "treats admins like paid users" do
      custom_sheet = create(:sheet, user: admin_user)
      starter_sheet = create(:sheet, :starter_rogue, user: admin_user)
      sign_in(admin_user)
      stub_bootstrap_for(user: admin_user, story: story, sheet: custom_sheet)

      post "/adventures", params: { story_id: story.id, sheet_id: custom_sheet.id }, as: :json
      expect(response).to have_http_status(:created)

      post "/adventures", params: { story_id: story.id, sheet_id: starter_sheet.id }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
