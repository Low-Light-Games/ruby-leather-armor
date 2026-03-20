require "rails_helper"

RSpec.describe "Player routes", type: :request do
  let(:user) { create(:user) }

  # Stubs current_user so we don't need to replicate OAuth session setup.
  before { sign_in_via_session(user) }

  describe "GET /sheets" do
    it "returns 200 (React SPA)" do
      get "/sheets"
      expect(response).to have_http_status(:ok)
    end

    context "when not authenticated" do
      before { sign_in_via_session(nil) }

      it "returns 200 even without auth (SPA shell is public)" do
        get "/sheets"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /adventures/new" do
    it "returns 200 (React SPA entry point)" do
      get "/adventures/new"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "JSON API endpoints" do
    describe "GET /stories" do
      it "returns 200 with JSON" do
        get "/stories", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
      end
    end

    describe "GET /sheets (JSON)" do
      it "returns 200 with the user's sheets" do
        create(:sheet, user: user)
        get "/sheets", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end
    end

    describe "GET /adventures (JSON)" do
      it "returns 200 with the user's adventures" do
        get "/adventures", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /feat_definitions" do
      it "returns 200" do
        get "/feat_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /spell_definitions" do
      it "returns 200" do
        get "/spell_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /item_definitions" do
      it "returns 200" do
        get "/item_definitions", headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /adventures/:id/update_micro_contexts" do
      let(:adventure) { create(:adventure, user: user) }
      let(:admin_user) { create(:user, :admin) }

      context "when authenticated as admin" do
        before { sign_in_via_session(admin_user) }

        it "returns 200 and updates the contexts" do
          new_context = { "current_location" => "Forest" }
          patch "/adventures/#{adventure.id}/update_micro_contexts",
                params: { traversal_context: new_context },
                headers: { "Accept" => "application/json" }
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to eq({ "success" => true })
          adventure.reload
          expect(adventure.traversal_context).to eq(new_context)
        end

        it "only updates provided contexts" do
          original_combat = adventure.combat_context
          patch "/adventures/#{adventure.id}/update_micro_contexts",
                params: { traversal_context: { "test" => "value" } },
                headers: { "Accept" => "application/json" }
          expect(response).to have_http_status(:ok)
          adventure.reload
          expect(adventure.traversal_context).to eq({ "test" => "value" })
          expect(adventure.combat_context).to eq(original_combat)
        end
      end

      context "when authenticated as non-admin" do
        it "returns 403" do
          patch "/adventures/#{adventure.id}/update_micro_contexts",
                params: { traversal_context: {} },
                headers: { "Accept" => "application/json" }
          expect(response).to have_http_status(:forbidden)
          expect(JSON.parse(response.body)).to eq({ "error" => "Unauthorized" })
        end
      end

      context "when not authenticated" do
        before { sign_in_via_session(nil) }

        it "returns 401" do
          patch "/adventures/#{adventure.id}/update_micro_contexts",
                params: { traversal_context: {} },
                headers: { "Accept" => "application/json" }
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end

  describe "unauthenticated access to protected routes" do
    before { sign_in_via_session(nil) }

    it "GET /adventures returns 401" do
      get "/adventures", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "GET /stories returns 401" do
      get "/stories", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
