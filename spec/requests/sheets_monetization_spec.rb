require "rails_helper"

RSpec.describe "Sheets monetization", type: :request do
  let(:free_user) { create(:user, :password_auth) }
  let(:paid_user) { create(:user, :password_auth, :paid) }
  let(:admin_user) { create(:user, :password_auth, :admin) }

  describe "POST /sheets" do
    let(:sheet_params) do
      {
        sheet: {
          name: "Custom Hero",
          character_class: "Fighter",
          race: "Human",
          level: 1,
          strength: 14,
          dexterity: 12,
          constitution: 13,
          intelligence: 10,
          wisdom: 11,
          charisma: 8
        }
      }
    end

    it "rejects free users" do
      sign_in(free_user)

      expect {
        post "/sheets", params: sheet_params, as: :json
      }.not_to change(Sheet, :count)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to include("error" => "Access denied")
    end

    it "allows paid users" do
      sign_in(paid_user)

      expect {
        post "/sheets", params: sheet_params, as: :json
      }.to change { paid_user.sheets.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to include("name" => "Custom Hero", "source_kind" => "custom")
    end
  end

  describe "starter sheet mutability" do
    let!(:starter_sheet) { create(:sheet, :starter_rogue, user: paid_user) }

    before { sign_in(paid_user) }

    it "rejects updates to starter sheets" do
      patch "/sheets/#{starter_sheet.id}", params: { sheet: { name: "Renamed" } }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(starter_sheet.reload.name).to eq("Maren Ashwick")
    end

    it "rejects deletes for starter sheets" do
      expect {
        delete "/sheets/#{starter_sheet.id}"
      }.not_to change(Sheet, :count)

      expect(response).to have_http_status(:forbidden)
      expect(starter_sheet.reload).to be_present
    end
  end

  describe "GET /sheets.json" do
    before do
      create(:sheet, user: paid_user, name: "Custom Sheet")
      create(:sheet, :starter_fighter, user: paid_user)
      sign_in(paid_user)
    end

    it "excludes starter sheets" do
      get "/sheets", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)

      payload = JSON.parse(response.body)
      expect(payload.map { |sheet| sheet["name"] }).to contain_exactly("Custom Sheet")
      expect(payload.map { |sheet| sheet["source_kind"] }).to contain_exactly("custom")
    end
  end

  describe "GET /sheets/adventure_options" do
    it "returns only starter sheets for free users and provisions them if missing" do
      sign_in(free_user)
      create(:sheet, user: free_user, name: "Free Custom")

      expect {
        get "/sheets/adventure_options", headers: { "Accept" => "application/json" }
      }.to change { free_user.sheets.starter.count }.by(2)

      expect(response).to have_http_status(:ok)

      payload = JSON.parse(response.body)
      expect(payload.map { |sheet| sheet["source_kind"] }.uniq).to eq(["starter"])
      expect(payload.map { |sheet| sheet["starter_key"] }).to contain_exactly("fighter", "rogue")
      expect(payload.map { |sheet| sheet["name"] }).not_to include("Free Custom")
    end

    it "returns only custom sheets for paid users" do
      create(:sheet, user: paid_user, name: "Paid Custom")
      create(:sheet, :starter_rogue, user: paid_user)
      sign_in(paid_user)

      get "/sheets/adventure_options", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)

      payload = JSON.parse(response.body)
      expect(payload.map { |sheet| sheet["name"] }).to contain_exactly("Paid Custom")
      expect(payload.map { |sheet| sheet["source_kind"] }).to contain_exactly("custom")
    end

    it "treats admins like paid users" do
      create(:sheet, user: admin_user, name: "Admin Custom")
      create(:sheet, :starter_fighter, user: admin_user)
      sign_in(admin_user)

      get "/sheets/adventure_options", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)

      payload = JSON.parse(response.body)
      expect(payload.map { |sheet| sheet["name"] }).to contain_exactly("Admin Custom")
    end
  end
end
