module AuthHelpers
  def sign_in(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  def sign_in_via_session(user)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
