# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Password resets", type: :request do
  describe "POST /password_resets" do
    let!(:user) { create(:user, :password_auth, email: "lost@example.com") }

    it "issues a reset token and enqueues the email when the user exists" do
      expect { post "/password_resets", params: { email: "lost@example.com" } }
        .to have_enqueued_mail(UserMailer, :password_reset)

      expect(response).to have_http_status(:ok)
      expect(user.reload.password_reset_token).to be_present
      expect(user.password_reset_sent_at).to be_present
    end

    it "silently no-ops for unknown emails so existence is not leaked" do
      expect { post "/password_resets", params: { email: "nobody@example.com" } }
        .not_to have_enqueued_mail(UserMailer, :password_reset)

      expect(response).to have_http_status(:ok)
    end

    it "skips OAuth users" do
      oauth_user = create(:user, email: "oauth@example.com", provider: "google_oauth2", uid: "abc")

      expect { post "/password_resets", params: { email: "oauth@example.com" } }
        .not_to have_enqueued_mail(UserMailer, :password_reset)

      expect(oauth_user.reload.password_reset_token).to be_nil
    end
  end

  describe "PATCH /password_resets/:token" do
    let!(:user) do
      create(:user, :password_auth, email: "resetting@example.com").tap(&:generate_password_reset!)
    end

    it "updates the password, clears the token, and signs the user in" do
      patch "/password_resets/#{user.password_reset_token}", params: {
        user: { password: "newpass1234", password_confirmation: "newpass1234" }
      }

      expect(response).to redirect_to(root_path)

      user.reload
      expect(user.password_reset_token).to be_nil
      expect(user.authenticate("newpass1234")).to be_truthy
    end

    it "rejects an expired token" do
      user.update!(password_reset_sent_at: 1.hour.ago)

      patch "/password_resets/#{user.password_reset_token}", params: {
        user: { password: "newpass1234", password_confirmation: "newpass1234" }
      }

      expect(response).to redirect_to(root_path(reset: "invalid"))
    end
  end
end
