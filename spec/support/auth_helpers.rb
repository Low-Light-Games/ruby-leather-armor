module AuthHelpers
  def sign_in(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  def sign_out
    delete "/logout"
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
