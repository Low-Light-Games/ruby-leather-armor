require "application_system_test_case"

class AuthFlowTest < ApplicationSystemTestCase
  setup do
    @admin = User.find_or_create_by!(email: 'admin@example.com') do |u|
      u.password_digest = BCrypt::Password.create('admin123')
      u.admin = true
    end
  end

  test "user can login and see their sheets" do
    visit root_path

    # Should see login form
    assert_selector "h1", text: "Character Sheet Login"
    
    # Fill in login form
    fill_in "Email", with: "admin@example.com"
    fill_in "Password", with: "admin123"
    click_button "Login"

    # Should be logged in and see the app
    assert_selector "h1", text: "Character Sheet", wait: 5
    assert_text "Logged in as: admin@example.com"
  end

  test "user cannot login with wrong password" do
    visit root_path

    fill_in "Email", with: "admin@example.com"
    fill_in "Password", with: "wrongpassword"
    click_button "Login"

    # Should still be on login page with error
    assert_selector "h1", text: "Character Sheet Login"
    assert_text "Invalid email or password", wait: 2
  end
end
