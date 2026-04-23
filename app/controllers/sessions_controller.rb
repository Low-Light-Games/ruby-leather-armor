class SessionsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]

  def new
    # Render login form
  end

  def create
    user = User.find_by(email: params[:email]&.downcase)
    
    if user && user.authenticate(params[:password])
      session[:user_id] = user.id
      render json: { user: user_json(user) }
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
      render json: { user: user_json(current_user) }
    else
      render json: { user: nil }
    end
  end

  private

  def user_json(user)
    {
      id: user.id,
      email: user.email,
      admin: user.admin,
      plan_key: user.plan_key,
      onboarding_state: user.onboarding_state,
      banned: user.banned?,
      trusted: user.trusted?,
      moderation_strikes: user.moderation_strikes,
      usage: {
        current_tokens: user.monthly_usage_tokens,
        limit_tokens: user.monthly_usage_limit,
        percentage: user.usage_percentage,
        limit_reached: user.usage_limit_reached?,
        delinquent: user.stripe_profile&.grace_period_ends_at.present?,
        grace_period_ends_at: user.stripe_profile&.grace_period_ends_at
      }
    }
  end
end
