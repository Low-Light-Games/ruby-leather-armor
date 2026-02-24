class SessionsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]

  def new
    # Render login form
  end

  def create
    user = User.find_by(email: params[:email]&.downcase)
    
    if user && user.authenticate(params[:password])
      session[:user_id] = user.id
      render json: { 
        user: { 
          id: user.id, 
          email: user.email, 
          admin: user.admin 
        } 
      }
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    session[:user_id] = nil
    render json: { message: 'Logged out successfully' }
  end

  def show
    if current_user
      render json: { 
        user: { 
          id: current_user.id, 
          email: current_user.email, 
          admin: current_user.admin 
        } 
      }
    else
      render json: { user: nil }
    end
  end
end
