class SessionsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]

  def new
    # Render login form
  end

  def create
    user = User.find_by(email: params[:email]&.downcase)
    
    if user && user.authenticate(params[:password])
      session[:user_id] = user.id
      session.delete(:oauth_new_signup)
      render json: { user: user_json(user) }
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    session[:user_id] = nil
    session.delete(:oauth_new_signup)
    render json: { message: 'Logged out successfully' }
  end

  def show
    if current_user
      render json: {
        user: user_json(current_user),
        oauth_new_signup: session.delete(:oauth_new_signup) == true
      }
    else
      render json: { user: nil }
    end
  end

  private

  def user_json(user)
    SessionUserPresenter.new(user: user).to_h
  end
end
