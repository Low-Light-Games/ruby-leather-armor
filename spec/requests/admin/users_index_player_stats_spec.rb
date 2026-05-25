require "rails_helper"

RSpec.describe "Admin users index — player message stats", type: :request do
  let(:admin_user) { create(:user, :admin, :password_auth) }
  let(:story)      { create(:story) }

  it "renders count + last-message timestamp per user, and 'never' for users with none" do
    user_with_msgs = create(:user, :password_auth)
    user_without   = create(:user, :password_auth)
    adventure = create(:adventure, user: user_with_msgs, story: story)

    travel_to(Time.zone.local(2026, 5, 1, 10, 0)) do
      adventure.adventure_messages.create!(
        role: "player", content: "I look around.", message_type: "narrative",
        user: user_with_msgs
      )
    end
    travel_to(Time.zone.local(2026, 5, 20, 14, 30)) do
      adventure.adventure_messages.create!(
        role: "player", content: "I draw my sword.", message_type: "narrative",
        user: user_with_msgs
      )
    end

    sign_in(admin_user)
    get admin_users_path

    expect(response).to have_http_status(:ok)

    with_msgs_row = response.body[/<tr[^>]*>(?:(?!<\/tr>).)*#{Regexp.escape(user_with_msgs.email)}(?:(?!<\/tr>).)*<\/tr>/m]
    without_row   = response.body[/<tr[^>]*>(?:(?!<\/tr>).)*#{Regexp.escape(user_without.email)}(?:(?!<\/tr>).)*<\/tr>/m]

    expect(with_msgs_row).to match(/col-msg-count[^>]*>\s*2\s*</)
    expect(with_msgs_row).to include("May 20 2026 14:30")
    expect(without_row).to include("never")
  end
end
