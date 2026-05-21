# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guest sessions", type: :request do
  describe "POST /guest_sessions" do
    context "when guest minting is disabled" do
      before { allow(Users::GuestFactory).to receive(:salt).and_return(nil) }

      it "returns 503" do
        post "/guest_sessions"
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context "when guest minting is enabled" do
      before { allow(Users::GuestFactory).to receive(:salt).and_return("test_salt") }

      it "creates a guest user keyed by the hashed IP" do
        expect { post "/guest_sessions" }.to change { User.where.not(guest_ip_hash: nil).count }.by(1)

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body.dig("user", "guest")).to be true
        expect(body.dig("user", "usage", "kind")).to eq("guest_lifetime")
      end

      it "returns the same guest on repeated calls from the same IP" do
        post "/guest_sessions"
        first_id = JSON.parse(response.body).dig("user", "id")

        post "/guest_sessions"

        expect(JSON.parse(response.body).dig("user", "id")).to eq(first_id)
        expect(User.where.not(guest_ip_hash: nil).count).to eq(1)
      end
    end
  end
end
