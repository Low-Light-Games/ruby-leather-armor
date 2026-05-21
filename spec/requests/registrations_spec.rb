# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "POST /signup" do
    let(:valid_params) do
      {
        email: "newbie@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    end

    it "creates a password user and starts a session" do
      expect { post "/signup", params: valid_params }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("user", "guest")).to be false
      expect(body.dig("user", "email_verified")).to be false
    end

    it "enqueues a verification email" do
      expect { post "/signup", params: valid_params }
        .to have_enqueued_mail(UserMailer, :verify_email)
    end

    it "absorbs a pre-existing guest at the same IP" do
      allow(Users::GuestFactory).to receive(:salt).and_return("test_salt")
      post "/guest_sessions"
      guest_id = JSON.parse(response.body).dig("user", "id")

      post "/signup", params: valid_params.merge(email: "absorbed@example.com")

      expect(User.exists?(guest_id)).to be false
      expect(JSON.parse(response.body).dig("user", "guest")).to be false
    end

    it "rejects mismatched password confirmation" do
      post "/signup", params: valid_params.merge(password_confirmation: "different!")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end

    it "rejects an invalid handle format" do
      post "/signup", params: valid_params.merge(handle: "ab")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
